{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE UndecidableInstances  #-}

module Nested where

import Peano

import Control.Applicative
import Control.Comonad
import Data.Foldable
import Data.Traversable
import Data.Distributive

data Flat x
data Nest o i

data Nested fs a where
   Flat :: f a -> Nested (Flat f) a
   Nest :: forall (f :: * -> *) fs a. Nested fs (f a) -> Nested (Nest fs f) a
   -- We need the explicit forall with kind signature to prevent ambiguity stemming from PolyKinds

type family UnNest x where
   UnNest (Nested (Flat f) a)    = f a
   UnNest (Nested (Nest fs f) a) = Nested fs (f a)

unNest :: Nested fs a -> UnNest (Nested fs a)
unNest (Flat x) = x
unNest (Nest x) = x

instance (Functor f) => Functor (Nested (Flat f)) where
   fmap f (Flat x) = Flat (fmap f x)

instance (Functor f, Functor (Nested fs)) => Functor (Nested (Nest fs f)) where
   fmap f (Nest x) = Nest (fmap (fmap f) x)

instance (Applicative f) => Applicative (Nested (Flat f)) where
   pure = Flat . pure
   Flat f <*> Flat x = Flat (f <*> x)

instance (Applicative f, Applicative (Nested fs)) => Applicative (Nested (Nest fs f)) where
   pure = Nest . pure . pure
   Nest f <*> Nest x = Nest ((<*>) <$> f <*> x)

instance (Comonad f) => Comonad (Nested (Flat f)) where
   extract   = extract . unNest
   duplicate = fmap Flat . Flat . duplicate . unNest

--   This might be an overly-general instance, because it would conflict with another possible
--   (valid) definition for the composition of two comonads, but which requires constraints we can't
--   satisfy with the comonads we're using. Namely, you can also instantiate this instance if you
--   replace @fmap distribute@ with @fmap sequenceA@ (from @Data.Traversable@), and let the resulting
--   instance have the constraints @(Comonad f, Comonad g, Traversable f, Applicative g)@. Since not
--   all of our comonads in this project are applicative, and no infinite structure (e.g. @Tape@) has
--   a good (i.e. not returning bottom in unpredictable ways) definition of @Traversable@, using the
--   @Distributive@ constraint makes much more sense here.
instance (Comonad f, Comonad (Nested fs), Distributive f, Functor (Nested (Nest fs f))) => Comonad (Nested (Nest fs f)) where
   extract   = extract . extract . unNest
   duplicate =
      fmap Nest . Nest   -- wrap it again: f (g (f (g a))) -> Nested (Nest f g) (Nested (Nest f g) a)
      . fmap distribute  -- swap middle two layers: f (f (g (g a))) -> f (g (f (g a)))
      . duplicate        -- duplicate outer functor f: f (g (g a)) -> f (f (g (g a)))
      . fmap duplicate   -- duplicate inner functor g: f (g a) -> f (g (g a))
      . unNest           -- NOTE: can't pattern-match on constructor or you break laziness!

instance (ComonadApply f) => ComonadApply (Nested (Flat f)) where
   Flat f <@> Flat x = Flat (f <@> x)

instance (ComonadApply f, Distributive f, ComonadApply (Nested fs)) => ComonadApply (Nested (Nest fs f)) where
   Nest f <@> Nest x =
      Nest ((<@>) <$> f <@> x)

type family AddNest x where
   AddNest (Nested fs (f x)) = Nested (Nest fs f) x

type family AsNestedAs x y where
   (f x) `AsNestedAs` (Nested (Flat g) b) = Nested (Flat f) x
   x     `AsNestedAs` y                   = AddNest (x `AsNestedAs` (UnNest y))

class NestedAs x y where
   asNestedAs :: x -> y -> x `AsNestedAs` y

instance ( AsNestedAs (f a) (Nested (Flat g) b) ~ Nested (Flat f) a )
         => NestedAs (f a) (Nested (Flat g) b) where
   x `asNestedAs` _ = Flat x

instance ( AsNestedAs (f a) (UnNest (Nested (Nest g h) b)) ~ Nested fs (f' a')
         , AddNest (Nested fs (f' a')) ~ Nested (Nest fs f') a'
         , NestedAs (f a) (UnNest (Nested (Nest g h) b)))
         => NestedAs (f a) (Nested (Nest g h) b) where
   x `asNestedAs` y = Nest (x `asNestedAs` (unNest y))

type family NestedCount x where
   NestedCount (Flat f)   = Succ Zero
   NestedCount (Nest f g) = Succ (NestedCount f)

nestedCount :: Nested f x -> Natural (NestedCount f)
nestedCount (Flat x) = Succ Zero
nestedCount (Nest x) = Succ (nestedCount x)

type family NestedNTimes n f where
   NestedNTimes (Succ Zero) f = Flat f
   NestedNTimes (Succ n)    f = Nest (NestedNTimes n f) f
