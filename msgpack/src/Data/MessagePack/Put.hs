{-# LANGUAGE LambdaCase #-}

--------------------------------------------------------------------
-- |
-- Module    : Data.MessagePack.Put
-- Copyright : © Hideyuki Tanaka 2009-2015
--           , © Herbert Valerio Riedel 2019
-- License   : BSD3
--
-- MessagePack Serializer using "Data.Binary".
--
--------------------------------------------------------------------

module Data.MessagePack.Put (
  putNil, putBool, putFloat, putDouble,
  putInt, putWord, putInt64, putWord64,
  putStr, putBin, putArray, putMap, putExt, putExt'
  ) where

import           Control.Applicative
import           Data.Bits
import qualified Data.ByteString          as S
import           Data.IntCast
import qualified Data.Text                as T
import qualified Data.Text.Encoding       as T
import qualified Data.Vector              as V

import           Prelude                  hiding (putStr)

import           Compat.Binary
import           Data.MessagePack.Integer
import           Data.MessagePack.Tags

putNil :: Put
putNil = putWord8 TAG_nil

putBool :: Bool -> Put
putBool False = putWord8 TAG_false
putBool True  = putWord8 TAG_true

-- | Encodes an 'Int' to MessagePack
--
-- See also 'MPInteger' and its 'Binary' instance.
putInt :: Int -> Put
putInt = put . toMPInteger

-- | @since 1.0.1.0
putWord :: Word -> Put
putWord = put . toMPInteger

-- | @since 1.0.1.0
putInt64 :: Int64 -> Put
putInt64 = put . toMPInteger

-- | @since 1.0.1.0
putWord64 :: Word64 -> Put
putWord64 = put . toMPInteger

putFloat :: Float -> Put
putFloat f = putWord8 TAG_float32 >> putFloat32be f

putDouble :: Double -> Put
putDouble d = putWord8 TAG_float64 >> putFloat64be d

putStr :: T.Text -> Put
putStr t = do
  let bs = T.encodeUtf8 t
  toSizeM ("putStr: data exceeds 2^32-1 byte limit of MessagePack") (S.length bs) >>= \case
    len | len < 32      -> putWord8 (TAG_fixstr .|. fromIntegral len)
        | len < 0x100   -> putWord8 TAG_str8  >> putWord8    (fromIntegral len)
        | len < 0x10000 -> putWord8 TAG_str16 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 TAG_str32 >> putWord32be (fromIntegral len)
  putByteString bs

putBin :: S.ByteString -> Put
putBin bs = do
  toSizeM ("putBin: data exceeds 2^32-1 byte limit of MessagePack") (S.length bs) >>= \case
    len | len < 0x100   -> putWord8 TAG_bin8  >> putWord8    (fromIntegral len)
        | len < 0x10000 -> putWord8 TAG_bin16 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 TAG_bin32 >> putWord32be (fromIntegral len)
  putByteString bs

putArray :: (a -> Put) -> V.Vector a -> Put
putArray p xs = do
  toSizeM ("putArray: data exceeds 2^32-1 element limit of MessagePack") (V.length xs) >>= \case
    len | len < 16      -> putWord8 (TAG_fixarray .|. fromIntegral len)
        | len < 0x10000 -> putWord8 TAG_array16 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 TAG_array32 >> putWord32be (fromIntegral len)
  V.mapM_ p xs

putMap :: (a -> Put) -> (b -> Put) -> V.Vector (a, b) -> Put
putMap p q xs = do
  toSizeM ("putMap: data exceeds 2^32-1 element limit of MessagePack") (V.length xs) >>= \case
    len | len < 16      -> putWord8 (TAG_fixmap .|. fromIntegral len)
        | len < 0x10000 -> putWord8 TAG_map16 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 TAG_map32 >> putWord32be (fromIntegral len)
  V.mapM_ (\(a, b) -> p a >> q b) xs

-- | __NOTE__: MessagePack is limited to maximum extended data payload size of \( 2^{32}-1 \) bytes.
putExt :: Word8 -> S.ByteString -> Put
putExt typ dat = do
  sz <- toSizeM "putExt: data exceeds 2^32-1 byte limit of MessagePack" (S.length dat)
  putExt' typ (sz, putByteString dat)

-- | @since 1.1.0.0
putExt' :: Word8 -- ^ type-tag of extended data
        -> (Word32,Put) -- ^ @(size-of-data, data-'Put'-action)@ (__NOTE__: it's the responsibility of the caller to ensure that the declared size matches exactly the data generated by the 'Put' action)
        -> Put
putExt' typ (sz,putdat) = do
  case sz of
    1                   -> putWord8 TAG_fixext1
    2                   -> putWord8 TAG_fixext2
    4                   -> putWord8 TAG_fixext4
    8                   -> putWord8 TAG_fixext8
    16                  -> putWord8 TAG_fixext16
    len | len < 0x100   -> putWord8 TAG_ext8  >> putWord8    (fromIntegral len)
        | len < 0x10000 -> putWord8 TAG_ext16 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 TAG_ext32 >> putWord32be (fromIntegral len)
  putWord8 typ
  putdat

----------------------------------------------------------------------------

toSizeM :: String -> Int -> PutM Word32
toSizeM label len0 = maybe (fail label) pure (intCastMaybe len0)
