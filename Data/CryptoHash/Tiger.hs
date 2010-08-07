{-# LANGUAGE ForeignFunctionInterface #-}

-- |
-- Module      : Data.CryptoHash.Tiger
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- A module containing Tiger bindings
--
module Data.CryptoHash.Tiger (
	Ctx(..),

	-- * Incremental hashing Functions
	init,      -- :: Ctx
	update,    -- :: Ctx -> ByteString -> Ctx
	finalize,  -- :: Ctx -> ByteString

	-- * Single Pass hashing
	hash,      -- :: ByteString -> ByteString
	hashlazy   -- :: ByteString -> ByteString
	) where

import Prelude hiding (init)
import Foreign
import Foreign.C.String
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Data.ByteString (ByteString)
import Data.ByteString.Unsafe (unsafeUseAsCStringLen, unsafeIndex)
import Data.ByteString.Internal (create)

data Ctx = Ctx ByteString

digestSize :: Int
sizeCtx :: Int

digestSize = 24
sizeCtx = 96

instance Storable Ctx where
	sizeOf _    = sizeCtx
	alignment _ = 16
	poke ptr (Ctx b) = mapM_ (\i -> poke (ptr `plusPtr` i) (unsafeIndex b i)) [0..(sizeCtx-1)]

	peek ptr = do
		b <- create sizeCtx (\bptr -> mapM_ (\i -> do
			f <- peek (ptr `plusPtr` i) :: IO Word8
			poke (bptr `plusPtr` i) f
			) [0..(sizeCtx-1)])
		return $ Ctx $! b

foreign import ccall unsafe "tiger.h tiger_init"
	c_tiger_init :: Ptr Ctx -> IO ()

foreign import ccall "tiger.h tiger_update"
	c_tiger_update :: Ptr Ctx -> CString -> Word32 -> IO ()

foreign import ccall unsafe "tiger.h tiger_finalize"
	c_tiger_finalize :: Ptr Ctx -> CString -> IO ()

allocInternal :: (Ptr Ctx -> IO a) -> IO a
allocInternal = alloca

allocInternalFrom :: Ctx -> (Ptr Ctx -> IO a) -> IO a
allocInternalFrom ctx f = allocInternal $ \ptr -> (poke ptr ctx >> f ptr)

updateInternalIO :: Ptr Ctx -> ByteString -> IO ()
updateInternalIO ptr d =
	unsafeUseAsCStringLen d (\(cs, len) -> c_tiger_update ptr cs (fromIntegral len))

finalizeInternalIO :: Ptr Ctx -> IO ByteString
finalizeInternalIO ptr =
	allocaBytes digestSize (\cs -> c_tiger_finalize ptr cs >> B.packCStringLen (cs, digestSize))

{-# NOINLINE init #-}
-- | init a context
init :: Ctx
init = unsafePerformIO $ allocInternal $ \ptr -> do (c_tiger_init ptr >> peek ptr)

{-# NOINLINE update #-}
-- | update a context with a bytestring
update :: Ctx -> ByteString -> Ctx
update ctx d = unsafePerformIO $ allocInternalFrom ctx $ \ptr -> do updateInternalIO ptr d >> peek ptr

{-# NOINLINE finalize #-}
-- | finalize the context into a digest bytestring
finalize :: Ctx -> ByteString
finalize ctx = unsafePerformIO $ allocInternalFrom ctx $ \ptr -> do finalizeInternalIO ptr

{-# NOINLINE hash #-}
-- | hash a strict bytestring into a digest bytestring
hash :: ByteString -> ByteString
hash d = unsafePerformIO $ allocInternal $ \ptr -> do
	c_tiger_init ptr >> updateInternalIO ptr d >> finalizeInternalIO ptr

{-# NOINLINE hashlazy #-}
-- | hash a lazy bytestring into a digest bytestring
hashlazy :: L.ByteString -> ByteString
hashlazy l = unsafePerformIO $ allocInternal $ \ptr -> do
	c_tiger_init ptr >> mapM_ (updateInternalIO ptr) (L.toChunks l) >> finalizeInternalIO ptr