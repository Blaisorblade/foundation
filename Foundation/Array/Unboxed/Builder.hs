{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Foundation.Array.Unboxed.Builder
    ( ArrayBuilder
    , appendTy
    , build
    ) where

import           Foundation.Array.Unboxed
import           Foundation.Array.Unboxed.Mutable
import           Foundation.Internal.Base
import           Foundation.Internal.MonadTrans
import           Foundation.Internal.Types
import           Foundation.Number
import           Foundation.Primitive.Monad
import           Foundation.Primitive.Types
import qualified Data.List

-- | A Array being built chunks by chunks
--
-- The previous buffers are in reverse order, and
-- this contains the current buffer and the state of
-- progress packing ty inside.
data ArrayBuildingState ty st = ArrayBuildingState
    { prevBuffers   :: [UArray ty]
    , currentBuffer :: MUArray ty st
    , currentOffset :: !(Offset ty)
    , chunkSize     :: !(Size ty)
    }

newtype ArrayBuilder ty st a = ArrayBuilder { runArrayBuilder :: State (ArrayBuildingState ty (PrimState st)) st a }
    deriving (Functor,Applicative,Monad)

appendTy :: (PrimMonad st, PrimType ty, Monad st) => ty -> ArrayBuilder ty st ()
appendTy v = ArrayBuilder $ State $ \st ->
    if offsetAsSize (currentOffset st) == chunkSize st
        then do
            newChunk <- new (chunkSize st)
            cur <- unsafeFreeze (currentBuffer st)
            write newChunk 0 v
            return ((), st { prevBuffers   = cur : prevBuffers st
                           , currentOffset = Offset 1
                           , currentBuffer = newChunk
                           })
        else do
            let (Offset ofs) = currentOffset st
            write (currentBuffer st) ofs v
            return ((), st { currentOffset = currentOffset st + Offset 1 })

build :: (PrimMonad prim, PrimType ty)
      => Int                     -- ^ size of chunks (elements)
      -> ArrayBuilder ty prim () -- ^ ..
      -> prim (UArray ty)
build sizeChunksI origab = call origab (Size sizeChunksI)
  where
    call :: (PrimType ty, PrimMonad prim)
         => ArrayBuilder ty prim () -> Size ty -> prim (UArray ty)
    call ab sizeChunks = do
        m        <- new sizeChunks
        ((), st) <- runState (runArrayBuilder ab) (ArrayBuildingState [] m (Offset 0) sizeChunks)
        current <- unsafeFreezeShrink (currentBuffer st) (offsetAsSize $ currentOffset st)
        return $ mconcat $ Data.List.reverse (current:prevBuffers st)
