{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE ScopedTypeVariables #-}

import Control.Applicative
import Control.Monad
import Control.Monad.Fix (fix)
import Control.Monad.Primitive
import Control.Monad.ST
import Data.Monoid
import Data.Primitive
import Data.Primitive.Array
import Data.Primitive.ByteArray
import Data.Primitive.Types
import Data.Primitive.SmallArray
import Data.Primitive.PrimArray
import Data.Word
import Data.Proxy (Proxy(..))
import GHC.Int
import GHC.IO
import GHC.Prim
#if MIN_VERSION_base(4,9,0)
import Data.Semigroup (stimes)
#endif

import Test.Tasty (defaultMain,testGroup,TestTree)
import Test.QuickCheck (Arbitrary,Arbitrary1,Gen)
import qualified Test.Tasty.QuickCheck as TQC
import qualified Test.QuickCheck as QC
import qualified Test.QuickCheck.Classes as QCC
import qualified Test.QuickCheck.Classes.IsList as QCCL
import qualified Data.List as L

main :: IO ()
main = do
  testArray
  testByteArray
  defaultMain $ testGroup "properties"
    [ testGroup "Array"
      [ lawsToTest (QCC.eqLaws (Proxy :: Proxy (Array Int)))
      , lawsToTest (QCC.ordLaws (Proxy :: Proxy (Array Int)))
      , lawsToTest (QCC.monoidLaws (Proxy :: Proxy (Array Int)))
      , lawsToTest (QCC.showReadLaws (Proxy :: Proxy (Array Int)))
#if MIN_VERSION_base(4,7,0)
      , lawsToTest (QCC.isListLaws (Proxy :: Proxy (Array Int)))
#endif
#if MIN_VERSION_base(4,9,0) || MIN_VERSION_transformers(0,4,0)
      , lawsToTest (QCC.functorLaws (Proxy1 :: Proxy1 Array))
      , lawsToTest (QCC.applicativeLaws (Proxy1 :: Proxy1 Array))
      , lawsToTest (QCC.monadLaws (Proxy1 :: Proxy1 Array))
      , lawsToTest (QCC.foldableLaws (Proxy1 :: Proxy1 Array))
      , lawsToTest (QCC.traversableLaws (Proxy1 :: Proxy1 Array))
#endif
      ]
    , testGroup "SmallArray"
      [ lawsToTest (QCC.eqLaws (Proxy :: Proxy (SmallArray Int)))
      , lawsToTest (QCC.ordLaws (Proxy :: Proxy (SmallArray Int)))
      , lawsToTest (QCC.monoidLaws (Proxy :: Proxy (SmallArray Int)))
      , lawsToTest (QCC.showReadLaws (Proxy :: Proxy (Array Int)))
#if MIN_VERSION_base(4,7,0)
      , lawsToTest (QCC.isListLaws (Proxy :: Proxy (SmallArray Int)))
#endif
#if MIN_VERSION_base(4,9,0) || MIN_VERSION_transformers(0,4,0)
      , lawsToTest (QCC.functorLaws (Proxy1 :: Proxy1 SmallArray))
      , lawsToTest (QCC.applicativeLaws (Proxy1 :: Proxy1 SmallArray))
      , lawsToTest (QCC.monadLaws (Proxy1 :: Proxy1 SmallArray))
      , lawsToTest (QCC.foldableLaws (Proxy1 :: Proxy1 SmallArray))
      , lawsToTest (QCC.traversableLaws (Proxy1 :: Proxy1 SmallArray))
#endif
      ]
    , testGroup "ByteArray"
      [ lawsToTest (QCC.eqLaws (Proxy :: Proxy ByteArray))
      , lawsToTest (QCC.ordLaws (Proxy :: Proxy ByteArray))
      , lawsToTest (QCC.showReadLaws (Proxy :: Proxy (Array Int)))
#if MIN_VERSION_base(4,7,0)
      , lawsToTest (QCC.isListLaws (Proxy :: Proxy ByteArray))
#endif
      ]
    , testGroup "PrimArray"
      [ lawsToTest (QCC.eqLaws (Proxy :: Proxy (PrimArray Word16)))
      , lawsToTest (QCC.ordLaws (Proxy :: Proxy (PrimArray Word16)))
#if MIN_VERSION_base(4,7,0)
      , lawsToTest (QCC.isListLaws (Proxy :: Proxy (PrimArray Word16)))
      , TQC.testProperty "foldrPrimArray" (QCCL.foldrProp int16 foldrPrimArray)
      , TQC.testProperty "foldrPrimArray'" (QCCL.foldrProp int16 foldrPrimArray')
      , TQC.testProperty "foldlPrimArray" (QCCL.foldlProp int16 foldlPrimArray)
      , TQC.testProperty "foldlPrimArray'" (QCCL.foldlProp int16 foldlPrimArray')
      , TQC.testProperty "foldlPrimArrayM'" (QCCL.foldlMProp int16 foldlPrimArrayM')
      , TQC.testProperty "mapPrimArray" (QCCL.mapProp int16 int32 mapPrimArray)
      , TQC.testProperty "traversePrimArray" (QCCL.traverseProp int16 int32 traversePrimArray)
      , TQC.testProperty "traversePrimArrayP" (QCCL.traverseProp int16 int32 traversePrimArrayP)
      , TQC.testProperty "imapPrimArray" (QCCL.imapProp int16 int32 imapPrimArray)
      , TQC.testProperty "itraversePrimArray" (QCCL.imapMProp int16 int32 itraversePrimArray)
      , TQC.testProperty "itraversePrimArrayP" (QCCL.imapMProp int16 int32 itraversePrimArrayP)
      , TQC.testProperty "generatePrimArray" (QCCL.generateProp int16 generatePrimArray)
      , TQC.testProperty "generatePrimArrayA" (QCCL.generateMProp int16 generatePrimArrayA)
      , TQC.testProperty "generatePrimArrayP" (QCCL.generateMProp int16 generatePrimArrayP)
      , TQC.testProperty "replicatePrimArray" (QCCL.replicateProp int16 replicatePrimArray)
      , TQC.testProperty "replicatePrimArrayA" (QCCL.replicateMProp int16 replicatePrimArrayA)
      , TQC.testProperty "replicatePrimArrayP" (QCCL.replicateMProp int16 replicatePrimArrayP)
      , TQC.testProperty "filterPrimArray" (QCCL.filterProp int16 filterPrimArray)
      , TQC.testProperty "filterPrimArrayA" (QCCL.filterMProp int16 filterPrimArrayA)
      , TQC.testProperty "mapMaybePrimArray" (QCCL.mapMaybeProp int16 int32 mapMaybePrimArray)
#endif
      ]
    ]

int16 :: Proxy Int16
int16 = Proxy

int32 :: Proxy Int32
int32 = Proxy

-- on GHC 7.4, Proxy is not polykinded, so we need this instead.
data Proxy1 (f :: * -> *) = Proxy1

lawsToTest :: QCC.Laws -> TestTree
lawsToTest (QCC.Laws name pairs) = testGroup name (map (uncurry TQC.testProperty) pairs)

testArray :: IO ()
testArray = do
    arr <- newArray 1 'A'
    let unit =
            case writeArray arr 0 'B' of
                IO f ->
                    case f realWorld# of
                        (# _, _ #) -> ()
    c1 <- readArray arr 0
    return $! unit
    c2 <- readArray arr 0
    if c1 == 'A' && c2 == 'B'
        then return ()
        else error $ "Expected AB, got: " ++ show (c1, c2)

testByteArray :: IO ()
testByteArray = do
    let arr1 = mkByteArray ([0xde, 0xad, 0xbe, 0xef] :: [Word8])
        arr2 = mkByteArray ([0xde, 0xad, 0xbe, 0xef] :: [Word8])
        arr3 = mkByteArray ([0xde, 0xad, 0xbe, 0xee] :: [Word8])
        arr4 = mkByteArray ([0xde, 0xad, 0xbe, 0xdd] :: [Word8])
        arr5 = mkByteArray ([0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xdd] :: [Word8])
    when (show arr1 /= "[0xde, 0xad, 0xbe, 0xef]") $
        fail $ "ByteArray Show incorrect: "++show arr1
    unless (arr1 > arr3) $
        fail $ "ByteArray Ord incorrect"
    unless (arr1 == arr2) $
        fail $ "ByteArray Eq incorrect"
    unless (mappend arr1 arr4 == arr5) $
        fail $ "ByteArray Monoid mappend incorrect"
    unless (mappend arr1 (mappend arr3 arr4) == mappend (mappend arr1 arr3) arr4) $
        fail $ "ByteArray Monoid mappend not associative"
    unless (mconcat [arr1,arr2,arr3,arr4,arr5] == (arr1 <> arr2 <> arr3 <> arr4 <> arr5)) $
        fail $ "ByteArray Monoid mconcat incorrect"
#if MIN_VERSION_base(4,9,0)
    unless (stimes (3 :: Int) arr4 == (arr4 <> arr4 <> arr4)) $
        fail $ "ByteArray Semigroup stimes incorrect"
#endif

mkByteArray :: Prim a => [a] -> ByteArray
mkByteArray xs = runST $ do
    marr <- newByteArray (length xs * sizeOf (head xs))
    sequence $ zipWith (writeByteArray marr) [0..] xs
    unsafeFreezeByteArray marr

instance Arbitrary1 Array where
  liftArbitrary elemGen = fmap fromList (QC.liftArbitrary elemGen)

instance Arbitrary a => Arbitrary (Array a) where
  arbitrary = fmap fromList QC.arbitrary

instance Arbitrary1 SmallArray where
  liftArbitrary elemGen = fmap smallArrayFromList (QC.liftArbitrary elemGen)

instance Arbitrary a => Arbitrary (SmallArray a) where
  arbitrary = fmap smallArrayFromList QC.arbitrary

instance Arbitrary ByteArray where
  arbitrary = do
    xs <- QC.arbitrary :: Gen [Word8]
    return $ runST $ do
      a <- newByteArray (L.length xs)
      iforM_ xs $ \ix x -> do
        writeByteArray a ix x
      unsafeFreezeByteArray a

instance (Arbitrary a, Prim a) => Arbitrary (PrimArray a) where
  arbitrary = do
    xs <- QC.arbitrary :: Gen [a]
    return $ runST $ do
      a <- newPrimArray (L.length xs)
      iforM_ xs $ \ix x -> do
        writePrimArray a ix x
      unsafeFreezePrimArray a


iforM_ :: Monad m => [a] -> (Int -> a -> m b) -> m ()
iforM_ xs0 f = go 0 xs0 where
  go !_ [] = return ()
  go !ix (x : xs) = f ix x >> go (ix + 1) xs

