>{-# LANGUAGE RankNTypes, FlexibleContexts, FlexibleInstances, TupleSections, MultiParamTypeClasses, FunctionalDependencies, PatternGuards #-}
>module Window
>    ( windowAggr
>    , window
>    , lastSecs
>    , lastPico
>    , lastRows
>     )
>    where

>import Data.Set(Set)
>import qualified Data.Set as Set
>import Data.Map(Map)
>import qualified Data.Map as Map
>import Data.Sequence(Seq, (|>), (<|), ViewR(..), ViewL(..))
>import qualified Data.Sequence as Seq

>import Data.Maybe as Maybe
>import Data.Monoid
>import Data.Time
>import Data.Time.Clock
>import Data.Tuple.All

>import Control.Arrow
>import Control.Category
>import Control.Monad

>import Queue
>import Timable
>import RelMap
>import Aggrs

>import Prelude hiding (null, reverse, id, (.))

>import qualified Data.FingerTree as FT
>import Data.FingerTree(FingerTree, Measured)

>import Control.Applicative (Applicative(pure, (<*>)), (<$>))
>import Data.Monoid
>import Data.Max
>import Data.Foldable (Foldable(foldMap), toList)
>import Data.Traversable (Traversable(traverse))


�����⢥���� 楫�� ⨯�-����⪨ Acc ���� ᤥ���� �������� �࠭���� �����⮣� ������� �
FingerTree. FingerTree �ॡ�� Measured, ���⮬� ��� (UTCTime, Acc a) ॠ����� Measured

>newtype Acc a = Acc { getAcc :: a }
>    deriving(Show)

>instance (Monoid a) => Measured (Max UTCTime, Sum Int, a) (UTCTime, Acc a) where
>    measure (t, a) = (Max t, Sum 1, getAcc a)

--------------------------------------
 ����

window' �ਭ����� 
 -2 ��࠭��⥫�: �� �६��� � �� �������� ����ᥩ
 -�㭪�� �� ����� � ������

�����頥��� ���祭�� - �� �⮡ࠦ���� �⭮襭��, ���஥ �࠭�� १���� � FingerTree
��㦥���� ���� FingerTree (Max UTCTime, Sum Int, b) �������� ����� ��室��� ����室��� ����
��室� �� ⥪�饣� �६��� � ������⢠ ����ᥩ.

������ ����祭��� ���祭�� ���������� � ��������, 
����� �������� - ���� 䨫����� ��ॢ� �㭪樥� restrictFT

��࠭��⥫� �।�⠢���� ᮡ��
 1)�㭪�� �� ⥪�饣� �६��� �� �६���� ࠬ��
 2)�㭪�� �� ������⢠ � ���� (��稭������, ������⢮���祭��). ������ ������⢮���祭��, 
    � �� �����稢����ᮬ, � ᥬ��⨪� restrictFT �।�⠢��� ᮡ�� (dropUntil _ . takeUntil _),
    � FingerTree ������뢠�� ������ ��᫥ ࠧ������ (dropUntil � takeUntil �� ��� ࠧ ࠧ������)

>window'
>  :: (Timable a, Monoid b) =>
>     Maybe (UTCTime -> (UTCTime, UTCTime))
>  -> Maybe (Int -> (Int, Int))
>  -> (a -> b)
>  -> RelMapGen
>     (FingerTree (Max UTCTime, Sum Int, b)) a (UTCTime, Acc b)
>window' tRestr cRestr fn = restrictor
>    where
>      r = mkFTSelector fn

>      restrictFT' = restrictFT tRestr cRestr

>      restrictor = restrictFT' `seq` RM (restrMapper (rmMapper r))  (rmAcc r)
>      restrMapper mapper el = let RM f acc = mapper el
>                              in RM (restrMapper f) (restrictFT' acc)

windowAggr, window - ��� ��宦�� �㭪樨, � ⮩ ࠧ��楩, �� 
windowAggr ᢮�稢��� १����(����) �� �������, ᮮ⢥��⢥���
windowAggr � �⫨稨 �� window ����� ��࠭�祭�� (Monoid b)

���� �㦥���� ���� FingerTree "(Max UTCTime, Sum Int, b)"
windowAggr ���頥��� � "b" �� �㦥����� ����, ����� � ᮤ�ন� ����室��� १����.
�.�. ������ �����ॢ� �࠭�� ����� १���� ᢥ�⪨ �������, 
������ १���� �� ᫥���饬 ����� �㤥� �祭� �����.(����॥ 祬 �� O(ln n))

�⮣�:
 ���������� ����� - �(1), 
 �뤥����� �㦭��� ���� �� �ॢ��� O(ln n), 
    � �筥� O(ln ((min (i, n) + min (n, j)))), 
    ��� n, i, j - ࠧ���� ����, ���⪠ ᫥��, ���⪠ �ࠢ� ᮮ⢥��⢥���
 

>windowAggr
>  :: (Timable a, Monoid b) =>
>     Maybe (UTCTime -> (UTCTime, UTCTime))
>  -> Maybe (Int -> (Int, Int))
>  -> (a -> b)
>  -> RelMap a b
>windowAggr tRestr cRestr fn = fromFn sel3 . (selector $ window' tRestr cRestr fn)
>    where
>      selector r = RM (mkMapper r) (rToAcc r)
>          where
>            rToAcc = Seq.singleton . FT.measure . rmAcc
>            mkMapper r el = RM (mkMapper r') (rToAcc r')
>                where r' = rmMapper r el

window - ���� ��࠭�稢��� १����, �� ����� �� �����. �⮡� ����� ��ᯮ�짮������
�㭪樥� window' "b" �㦭� ᤥ���� ��������, ���⮬� ��� ��� ஫� ᣮ������ �� ������, 
�� ����騩 ��࠭�祭�� �� ⨯, ���ਬ�� First.
���⮬� � �㭪�� window' ��।���� ��������� ��㬥��-�㭪樨 � ��������� First,
� १���� ���쬥� ������� �� Just.

>window :: (Timable a) =>
>          Maybe (UTCTime -> (UTCTime, UTCTime))
>       -> Maybe (Int     -> (Int, Int))
>       -> (a -> b)
>       -> RelMap a b
>window tRestr cRestr fn = selector `rmComp` window' tRestr cRestr (First . Just . fn)
>                          -- `rmComp` (fromFn (First . Just))
>    where selector :: RelMap (UTCTime, Acc (First b)) b
>          selector = fromFn f
>              where f (_, Acc (First (Just b))) = b



>mkFTSelector :: (Timable a, Monoid b) =>
>              (a -> b)
>           -> RelMapGen (FingerTree (Max UTCTime, Sum Int, b)) a (UTCTime, Acc b)
>mkFTSelector fn = RM (mkMapper FT.empty) FT.empty
>    where
>      f a = (toTime a, Acc $ fn a)
>      mkMapper acc el = RM (mkMapper acc') acc'
>          where acc' = acc FT.|> f el	-- FIXME? FT.|

--------------------------------------

restrictFT - �㭪��, �ਭ������ 2 ��࠭��⥫� �� �६��� � ��������,
��������� �⮡ࠦ���� FingerTree, � ������, ��࠭�稢��� �����.

>restrictFT :: (Monoid b) =>
>              Maybe (UTCTime -> (UTCTime, UTCTime))	-- from/to time producer
>           -> Maybe (Int     -> (Int, Int))		-- from/to count producer
>           -> FingerTree (Max UTCTime, Sum Int, b) (UTCTime, Acc b)
>           -> FingerTree (Max UTCTime, Sum Int, b) (UTCTime, Acc b)
>restrictFT restrT restrC inpFT = (FT.takeUntil tPred . FT.dropUntil dPred $ inpFT)
>    where
>      (Max curTime, Sum count, _) = FT.measure inpFT

>      -- FIXME?
>      (minIdx, maxIdx)   = Maybe.fromMaybe (const (minBound, maxBound)) restrC $ count
>      (minTime, maxTime) = Maybe.fromMaybe (const (minBound, maxBound)) restrT $ curTime

>      -- take/drop while
>      tPred (Max time, Sum number, _) = not (time < maxTime && number < maxIdx)
>      dPred (Max time, Sum number, _) = not (time < minTime || number < minIdx)

------------------------------------------------------------------------------
����� ���� ����� �㭪権, ��� 㤮���� ࠡ���,
ᯮᮡ� ����ந�� ��࠭��⥫� �� Integer, NominalDiffTime � �

>lastSecs :: Integer -> Maybe (UTCTime -> (UTCTime, UTCTime))
>lastSecs n = Just f
>    where
>      f curTime = (minTime, curTime)
>          where minTime = addUTCTime (fromInteger (-n)) curTime

>lastPico :: NominalDiffTime -> Maybe (UTCTime -> (UTCTime, UTCTime))
>lastPico n = Just f
>    where
>      f curTime = (minTime, curTime)
>          where minTime = addUTCTime (-n) curTime

>lastRows :: (Num a, Bounded a) => a -> Maybe (a -> (a, a))
>lastRows n = Just f
>    where
>      f count = (minRow, maxBound)
>          where minRow = count - n + 1

------------------------------------------------------------------------------
�㭪樨 ��� �஢�ન �ந�����⥫쭮��
�� �㭪樨 ����᪠���� �� 10 000 �室��� ������� � ��ࠡ��뢠�� ����॥ 祬 �� ���ᥪ㭤�.
� 楫�� ����稫��� ����॥, 祬 ��⨬����� ��㯯���. �஬� ⮣� ��� ���᪠ �㦭��� ���� 
�㦭� ����� O(ln n), ���⮬� �஢�ન ���� ���� �����筮 ����ᮥ����� � �� �� ᨫ쭮 
������� �� ����� �ந�����⥫쭮���.

�⮨� ⠪�� �⬥���, �� mainAg1 �� ᨫ쭮 �⫨砥��� �� mainAg2, �� ����祭���� �६���,
� ������, �� ���஬� �ந�室��� ᢥ�⪠ ��⠫�� ������ - �.�. �� ����⢨⥫쭮� ����� �� ᢥ���� ������,
��祬 �� ����⠫ ᢥ�⪨ ��� ᢮�� �஬������� 㧫�� - �����ॢ쥢, ����� �� �ਤ���� 
����� �� ᫥���饬 ���饭��. �� ���� ����� �ந�����⥫쭮�� �� ����� ������, � �� �������� ������.
� ����⢥ �������樨 �ਢ����� �㭪樨 mainAg2' � mainAg1', ����� ��ࠡ��뢠�� 20 000 ������ �
�믮����� ����� ����� 10 000. mainAg2' ��ࠡ�⠫� �� 0.623249s ��⨢ mainAg1', ��ࠡ�⠢襩 ��
0.828081s


>rowToProc = 10000
>rowWind   = 50

>timeM :: (Show a) => IO a -> IO ()
>timeM a = do
>  t <- getCurrentTime
>  a >>= print
>  t' <- getCurrentTime
>  print (t' `diffUTCTime` t)

>mkTimedList :: (Num a, Enum a) => Int -> IO [(UTCTime, a)]
>mkTimedList n = mapM fn (take n [1..])
>    where fn n = getCurrentTime >>= return . (,n)

���� ��� ��ॣ�樨 �� �������� ����ᥩ (~0.40845s)

>test :: IO ()
>test = do
>  let t = window Nothing (lastRows rowWind) (Product . sel2)
>      test  x = do
>         timedList <- mkTimedList x
>         return $ feedElms t timedList
>  timeM $ test rowToProc
>  return ()

 ��ॣ��� �१ ��������� (~0.410508s)

>testAg1 :: IO ()
>testAg1 = do
>  let t = window Nothing (lastRows rowWind) (Product . sel2)
>      test  x = do
>         timedList <- mkTimedList x
>         return $ feedElms (foldyRM mappend mempty . t) timedList
>  timeM $ test rowToProc
>  return ()

 2 ��ॣ��� �१ ��������� (~0.828081s)

>testAg1' :: IO ()
>testAg1' = do
>  let t = window Nothing (lastRows rowWind) (Product . sel2)
>      test  x = do
>         timedList1 <- mkTimedList x
>         timedList2 <- mkTimedList x
>         let r1 = feedElms (foldyRM mappend mempty . t) timedList1
>             r2 = feedElms r1 timedList2
>         return (r1, r2)
>  timeM $ test rowToProc
>  return ()

 ��ॣ��� �१ �㭪�� windowAggr (~0.422327s)

>testAg2 :: IO ()
>testAg2 = do
>  let t = windowAggr Nothing (lastRows rowWind) (Product . sel2)
>      test  x = do
>         timedList <- mkTimedList x
>         return $ feedElms t timedList
>  timeM $ test rowToProc
>  return ()


 2 ��ॣ��� �१ �㭪�� windowAggr (~0.623249s)

>testAg2' :: IO ()
>testAg2' = do
>  let t = windowAggr Nothing (lastRows rowWind) (Product . sel2)
>      test  x = do
>         timedList1 <- mkTimedList x
>         timedList2 <- mkTimedList x
>         let r1 = feedElms t timedList1
>             r2 = feedElms r1 timedList1
>         return (r1,r2)
>  timeM $ test rowToProc
>  return ()

 ���� ��� ��ॣ�樨, �� �६��� (~0.416505s)

>test1 :: IO ()
>test1 = do
>  let test  x = do
>          timedList <- mkTimedList x
>          let diff = fst (timedList !! rowWind) `diffUTCTime` fst (timedList !! 0)
>              t = window (lastPico diff) Nothing (Max *** Product)
>          print diff
>          return $ feedElms t timedList
>  timeM $ test rowToProc
>  return ()
