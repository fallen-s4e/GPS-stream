{-# LANGUAGE PatternGuards, MultiParamTypeClasses, FunctionalDependencies #-}
module RelMap
    where

import Data.Foldable
import Data.Tuple.All
import Data.Time		as Time
import Data.Time.Clock		as Time
import Data.Monoid
import Data.Function(on)
import qualified Data.List  as List
import Data.Maybe as Maybe
import Data.ByteString.Internal as BS
import qualified Data.Sequence as Seq
import Data.Sequence(Seq, (<|), (|>), ViewL(..), ViewR(..), (><))
import qualified Data.Set as Set
import Data.Set(Set)

import System.Random
import System.ZMQ as ZMQ

import Control.Applicative
import Control.Arrow
import Control.Category
import Control.Monad
import Control.Monad.Identity

import Prelude hiding((.), id, foldl, foldr)

import Relation
import Undable
import Utils
import TupleApply

--------------------------------------------------------------------------------
-----------------------------   data structure and api   -----------------------
--------------------------------------------------------------------------------
data RelMap inp outp = RM
    { rmMapper 	:: inp -> RelMap inp outp
    , rmAcc	:: Seq outp
    }

------------------------------
fromFnMb 	  :: (a -> Maybe b) -> RelMap a b
fromFnMb fn =  RM (mkMapper Seq.empty) Seq.empty
    where mkMapper s inp
              | Just outp <- fn inp 	= let s' = (s |> outp)
                                          in s' `seq` RM (mkMapper s') s'
              | otherwise		= RM (mkMapper s) s

fromFn :: (a -> b) -> RelMap a b
fromFn = fromFnMb . (Just .)

-- produces unfeedable RelMaps
fromSeq :: Seq outp -> RelMap inp outp
fromSeq s = rm
    where rm = RM (const rm) s

feedSeq :: RelMap inp out -> Seq inp -> RelMap inp out
feedSeq rm@(RM fn _) s = f (Seq.viewl s)
    where f (left :< rest) = feedSeq (fn left) rest
          f Seq.EmptyL	   = rm

feedList :: RelMap inp out -> [inp] -> RelMap inp out
feedList rm [] 	   		= rm
feedList rm@(RM fn _) (x:xs) 	= feedList (fn x) xs

foldyRM :: (a -> b -> b) -> b -> RelMap a b
foldyRM fn zero = RM (mkMapper seqZero) seqZero
    where mkMapper acc el = acc' `seq` RM (mkMapper acc') acc'
              where acc' = fmap (fn el $!) acc -- FIXME
          seqZero = Seq.singleton zero

--------------------------------------------------------------------------------
------------------------------   instances  ------------------------------------
--------------------------------------------------------------------------------
instance (Show outp) => Show (RelMap inp outp) where
    showsPrec _ (RM _ seq) = ("RM _ " ++) . (show seq ++)

instance Category RelMap where
    id = RM (mkMapper Seq.empty) Seq.empty
        where mkMapper acc inp = RM (mkMapper acc) (acc |> inp)

    rm2@(RM fn2 acc2) . rm1@(RM fn1 acc1) = RM fn3 acc3
        where fn3 inp 	= rm2 . fn1 inp
              acc3 	= rmAcc $ feedSeq rm2 acc1

instance Relation (RelMap inp) where
    (RM fn1 acc1) `union` rm2@(RM fn2 acc2) = RM fn3 acc3
        where acc3   = acc1 >< acc2
              fn3 el = fn1 el `union` fn2 el

    projection fn ra = ra >>> fromFn fn

    selection p ra   = ra >>> fromFnMb (toMaybeFn p)

    RM fn1 acc1 `minus` RM fn2 acc2 = RM fn3 acc3
        where acc3   = acc1 `seqDiff` acc2
              fn3 el = fn1 el `minus` fn2 el

    -- other
    a `insert` RM fn acc =  RM (\el -> a `insert` fn el) (acc |> a)

    rempty		 =  fromSeq Seq.empty

    joinG p s (RM fn1 acc1) (RM fn2 acc2) = RM fn3 acc3
        where acc3    = joinGSeq p s acc1 acc2
              fn3 inp = joinG p s (fn1 inp) (fn2 inp)
--    partition   	 =  undefined

joinGSeq :: (a -> b -> Bool) -> (a -> b -> c)
         -> Seq a -> Seq b -> Seq c
joinGSeq p s s1 s2 = Utils.flattenS $ fmap fn s1
    where
      fn el1 = foldr fn' Seq.empty s2
          where
            fn' el2 acc | p el1 el2  = s el1 el2 <| acc

instance Functor (RelMap inp) where
    fmap = projection

instance Applicative (RelMap inp) where
    pure  = (`insert` rempty)

    RM fn1 acc1 <*> rm2@(RM _ acc2) = RM fn3 acc3
        where acc3 = flattenS $ fmap fn acc1
                  where fn f = fmap f acc2
              fn3 el = fn1 el <*> rm2

------------------------------------
------ some bad ideas

instance Monad (RelMap inp) where
    return = pure

    -- ignores produced functions
    RM fn1 acc1 >>= prm2 = RM fn3 acc3
        where fn3 el = fn1 el >>= prm2
              acc3 = flattenS . fmap (rmAcc . prm2) $ acc1

instance (Read outp) => Read (RelMap inp outp) where
    readsPrec _ str | "RM _ " `List.isPrefixOf` str =
                        let cuttedStr = drop 5 str
                        in [(first fromSeq r) | r <- reads cuttedStr]
                    | otherwise			    = []
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
