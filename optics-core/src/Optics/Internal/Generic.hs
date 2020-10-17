{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_HADDOCK not-home #-}

-- This module is intended for internal use only, and may change without warning
-- in subsequent releases.
module Optics.Internal.Generic
  ( generic
  , generic1
  , _V1
  , _U1
  , _Par1
  , _Rec1
  , _K1
  , _M1
  , _L1
  , _R1
  -- * Fields
  , GFieldImpl(..)
  , GFieldSum(..)
  , GFieldProd(..)
  , GAffineFieldImpl(..)
  , GAffineFieldSum(..)
  -- * Positions
  , GPositionImpl(..)
  , GPositionSum(..)
  -- * Constructors
  , GConstructorImpl(..)
  , GConstructorSum(..)
  , GConstructorTuple(..)
  -- * Types
  , GPlateImpl(..)
  , GPlateInner(..)
  -- * Re-export
  , module Optics.Internal.Generic.TypeLevel
  ) where

import Data.Kind
import Data.Type.Bool
import GHC.Generics
import GHC.TypeLits

import Optics.AffineTraversal
import Optics.Internal.Generic.TypeLevel
import Optics.Internal.Optic
import Optics.Iso
import Optics.Lens
import Optics.Prism
import Optics.Traversal

----------------------------------------
-- GHC.Generics

-- | Convert from the data type to its representation (or back)
--
-- >>> view (generic % re generic) "hello" :: String
-- "hello"
--
generic :: (Generic a, Generic b) => Iso a b (Rep a c) (Rep b c)
generic = iso from to

-- | Convert from the data type to its representation (or back)
generic1 :: (Generic1 f, Generic1 g) => Iso (f a) (g b) (Rep1 f a) (Rep1 g b)
generic1 = iso from1 to1

_V1 :: Lens (V1 s) (V1 t) a b
_V1 = lensVL (\_ -> \case {})

_U1 :: Iso (U1 p) (U1 q) () ()
_U1 = iso (const ()) (const U1)

_Par1 :: Iso (Par1 p) (Par1 q) p q
_Par1 = coerced

_Rec1 :: Iso (Rec1 f p) (Rec1 g q) (f p) (g q)
_Rec1 = coerced

_K1 :: Iso (K1 i c p) (K1 j d q) c d
_K1 = coerced

_M1 :: Iso (M1 i c f p) (M1 j d g q) (f p) (g q)
_M1 = coerced

_L1 :: Prism ((a :+: c) t) ((b :+: c) t) (a t) (b t)
_L1 = prism L1 reviewer
  where
    reviewer (L1 v) = Right v
    reviewer (R1 v) = Left (R1 v)

_R1 :: Prism ((c :+: a) t) ((c :+: b) t) (a t) (b t)
_R1 = prism R1 reviewer
  where
    reviewer (R1 v) = Right v
    reviewer (L1 v) = Left (L1 v)

----------------------------------------
-- Field

class GFieldImpl (name :: Symbol) s t a b where
  gfieldImpl :: Lens s t a b

instance
  ( Generic s
  , Generic t
  , path ~ GetFieldPaths s name (Rep s)
  , GFieldSum name path (Rep s) (Rep t) a b
  ) => GFieldImpl name s t a b where
  gfieldImpl = withLens
    (lensVL (\f s -> to <$> gfieldSum @name @path f (from s)))
    (\get set -> lensVL $ \f s -> set s <$> f (get s))
  {-# INLINE gfieldImpl #-}

----------------------------------------

class GFieldSum (name :: Symbol) (path :: PathTree ()) g h a b where
  gfieldSum :: LensVL (g x) (h x) a b

instance
  ( GFieldSum name path g h a b
  ) => GFieldSum name path (M1 D m g) (M1 D m h) a b where
  gfieldSum f (M1 x) = M1 <$> gfieldSum @name @path f x

instance
  ( GFieldSum name path1 g1 h1 a b
  , GFieldSum name path2 g2 h2 a b
  ) => GFieldSum name ('PathTree path1 path2) (g1 :+: g2) (h1 :+: h2) a b where
  gfieldSum f (L1 x) = L1 <$> gfieldSum @name @path1 f x
  gfieldSum f (R1 y) = R1 <$> gfieldSum @name @path2 f y
  {-# INLINE gfieldSum #-}

instance
  ( path ~ FromRight
      (TypeError
       ('Text "Data constructor " ':<>: QuoteSymbol con ':<>:
        'Text " doesn't have a field named " ':<>: QuoteSymbol name))
      epath
  , GFieldProd path g h a b
  ) => GFieldSum name ('PathLeaf epath) (M1 C ('MetaCons con fix hs) g) (M1 C m h) a b where
  gfieldSum f (M1 x) = M1 <$> gfieldProd @path f x

class GFieldProd (path :: [Path]) g h a b where
  gfieldProd :: LensVL (g x) (h x) a b

-- fast path left
instance
  ( GFieldProd path g1 h1 a b
  ) => GFieldProd ('PathLeft : path) (g1 :*: g2) (h1 :*: g2) a b where
  gfieldProd f (x :*: y) = (:*: y) <$> gfieldProd @path f x

-- slow path left
instance {-# INCOHERENT #-}
  ( GFieldProd path g1 h1 a b
  , g2 ~ h2
  ) => GFieldProd ('PathLeft : path) (g1 :*: g2) (h1 :*: h2) a b where
  gfieldProd f (x :*: y) = (:*: y) <$> gfieldProd @path f x

-- fast path right
instance
  ( GFieldProd path g2 h2 a b
  ) => GFieldProd ('PathRight : path) (g1 :*: g2) (g1 :*: h2) a b where
  gfieldProd f (x :*: y) = (x :*:) <$> gfieldProd @path f y

-- slow path right
instance {-# INCOHERENT #-}
  ( GFieldProd path g2 h2 a b
  , g1 ~ h1
  ) => GFieldProd ('PathRight : path) (g1 :*: g2) (h1 :*: h2) a b where
  gfieldProd f (x :*: y) = (x :*:) <$> gfieldProd @path f y

instance
  ( g ~ Rec0 a
  , h ~ Rec0 b
  ) => GFieldProd path (M1 S m g) (M1 S m h) a b where
  gfieldProd f (M1 (K1 x)) = M1 . K1 <$> f x

----------------------------------------
-- Affine field

class GAffineFieldImpl (name :: Symbol) s t a b where
  gafieldImpl :: AffineTraversal s t a b

instance
  ( Generic s
  , Generic t
  , path ~ GetFieldPaths s name (Rep s)
  , If (AnyHasPath path)
       (() :: Constraint)
       (TypeError
        ('Text "Type " ':<>: QuoteType s ':<>:
         'Text " doesn't have a field named " ':<>: QuoteSymbol name))
  , GAffineFieldSum path (Rep s) (Rep t) a b
  ) => GAffineFieldImpl name s t a b where
  gafieldImpl = withAffineTraversal
    (atraversalVL (\point f s -> to <$> gafieldSum @path point f (from s)))
    (\match update -> atraversalVL $ \point f s ->
        either point (fmap (update s) . f) (match s))
  {-# INLINE gafieldImpl #-}

----------------------------------------

class GAffineFieldSum (path :: PathTree ()) g h a b where
  gafieldSum :: AffineTraversalVL (g x) (h x) a b

instance
  ( GAffineFieldSum path g h a b
  ) => GAffineFieldSum path (M1 D m g) (M1 D m h) a b where
  gafieldSum point f (M1 x) = M1 <$> gafieldSum @path point f x

instance
  ( GAffineFieldSum path1 g1 h1 a b
  , GAffineFieldSum path2 g2 h2 a b
  ) => GAffineFieldSum ('PathTree path1 path2) (g1 :+: g2) (h1 :+: h2) a b where
  gafieldSum point f (L1 x) = L1 <$> gafieldSum @path1 point f x
  gafieldSum point f (R1 y) = R1 <$> gafieldSum @path2 point f y
  {-# INLINE gafieldSum #-}

instance
  ( GAffineFieldMaybe epath g h a b
  ) => GAffineFieldSum ('PathLeaf epath) (M1 C m g) (M1 C m h) a b where
  gafieldSum point f (M1 x) = M1 <$> gafieldMaybe @epath point f x

class GAffineFieldMaybe (epath :: Either () [Path]) g h a b where
  gafieldMaybe :: AffineTraversalVL (g x) (h x) a b

-- fast path
instance GAffineFieldMaybe ('Left '()) g g a b where
  gafieldMaybe point _ g = point g

-- slow path
instance {-# INCOHERENT #-}
  ( g ~ h
  ) => GAffineFieldMaybe ('Left '()) g h a b where
  gafieldMaybe point _ g = point g

instance
  ( GFieldProd prodPath g h a b
  ) => GAffineFieldMaybe ('Right prodPath) g h a b where
  gafieldMaybe _ f g = gfieldProd @prodPath f g

----------------------------------------
-- Position

class GPositionImpl (n :: Nat) s t a b where
  gpositionImpl :: Lens s t a b

instance
  ( Generic s
  , Generic t
  , path ~ If (n <=? 0)
              (TypeError ('Text "There is no 0th position"))
              (GetPositionPaths s n (Rep s))
  , GPositionSum n path (Rep s) (Rep t) a b
  ) => GPositionImpl n s t a b where
  gpositionImpl = withLens
    (lensVL (\f s -> to <$> gpositionSum @n @path f (from s)))
    (\get set -> lensVL $ \f s -> set s <$> f (get s))
  {-# INLINE gpositionImpl #-}

----------------------------------------

class GPositionSum (n :: Nat) (path :: PathTree Nat) g h a b where
  gpositionSum :: LensVL (g x) (h x) a b

instance
  ( GPositionSum n path g h a b
  ) => GPositionSum n path (M1 D m1 g) (M1 D m2 h) a b where
  gpositionSum f (M1 x) = M1 <$> gpositionSum @n @path f x

instance
  ( GPositionSum n path1 g1 h1 a b
  , GPositionSum n path2 g2 h2 a b
  ) => GPositionSum n ('PathTree path1 path2) (g1 :+: g2) (h1 :+: h2) a b where
  gpositionSum f (L1 x) = L1 <$> gpositionSum @n @path1 f x
  gpositionSum f (R1 y) = R1 <$> gpositionSum @n @path2 f y
  {-# INLINE gpositionSum #-}

instance
  ( path ~ If (IsRight epath)
      (FromRight Any epath)
      (TypeError
       ('Text "Data constructor " ':<>: QuoteSymbol con ':<>:
        'Text " has " ':<>: 'ShowType (FromLeft Any epath) ':<>:
        'Text " fields, " ':<>: ToOrdinal n ':<>: 'Text " requested"))
  , GFieldProd path g h a b
  ) => GPositionSum n ('PathLeaf epath) (M1 C ('MetaCons con fix hs) g) (M1 C m h) a b where
  gpositionSum f (M1 x) = M1 <$> gfieldProd @path f x

----------------------------------------
-- Constructor

class GConstructorImpl (name :: Symbol) s t a b where
  gconstructorImpl :: Prism s t a b

instance
  ( Generic s
  , Generic t
  , path ~ FromRight
    (TypeError
      ('Text "Type " ':<>: QuoteType s ':<>:
       'Text " doesn't have a constructor named " ':<>: QuoteSymbol name))
    (GetNamePath name (Rep s) '[])
  , GConstructorSum path (Rep s) (Rep t) a b
  ) => GConstructorImpl name s t a b where
  gconstructorImpl = withPrism (generic % gconstructorSum @path) prism
  {-# INLINE gconstructorImpl #-}

----------------------------------------

class GConstructorSum (path :: [Path]) g h a b where
  gconstructorSum :: Prism (g x) (h x) a b

instance
  ( GConstructorSum path g h a b
  ) => GConstructorSum path (M1 D m g) (M1 D m h) a b where
  gconstructorSum = _M1 % gconstructorSum @path

-- fast path left
instance
  ( GConstructorSum path g1 h1 a b
  ) => GConstructorSum ('PathLeft : path) (g1 :+: g2) (h1 :+: g2) a b where
  gconstructorSum = _L1 % gconstructorSum @path

-- slow path left
instance {-# INCOHERENT #-}
  ( GConstructorSum path g1 h1 a b
  , g2 ~ h2
  ) => GConstructorSum ('PathLeft : path) (g1 :+: g2) (h1 :+: h2) a b where
  gconstructorSum = _L1 % gconstructorSum @path

-- fast path right
instance
  ( GConstructorSum path g2 h2 a b
  ) => GConstructorSum ('PathRight : path) (g1 :+: g2) (g1 :+: h2) a b where
  gconstructorSum = _R1 % gconstructorSum @path

-- slow path right
instance {-# INCOHERENT #-}
  ( GConstructorSum path g2 h2 a b
  , g1 ~ h1
  ) => GConstructorSum ('PathRight : path) (g1 :+: g2) (h1 :+: h2) a b where
  gconstructorSum = _R1 % gconstructorSum @path

instance
  ( GConstructorTuple g h a b
  ) => GConstructorSum '[] (M1 C m g) (M1 C m h) a b where
  gconstructorSum = _M1 % gconstructorTuple

class GConstructorTuple g h a b where
  gconstructorTuple :: Prism (g x) (h x) a b

-- Fon uncluttering types in below instances a bit.
type F m a = M1 S m (Rec0 a)

instance {-# INCOHERENT #-}
  ( TypeError
    ('Text "Generic based access supports constructors" ':$$:
     'Text "containing up to 5 fields. Please generate" ':$$:
     'Text "PrismS with Template Haskell if you need more.")
  ) => GConstructorTuple g h a b where
  gconstructorTuple = error "unreachable"

instance
  ( a ~ ()
  , b ~ ()
  ) => GConstructorTuple U1 U1 a b where
  gconstructorTuple = castOptic _U1
  {-# INLINE gconstructorTuple #-}

instance
  ( r ~ a
  , s ~ b
  ) => GConstructorTuple (F m a) (F m b) r s where
  gconstructorTuple = castOptic coerced
  {-# INLINE gconstructorTuple #-}

instance
  ( r ~ (a1, a2)
  , s ~ (b1, b2)
  ) => GConstructorTuple
         (F m1 a1 :*: F m2 a2)
         (F m1 b1 :*: F m2 b2) r s where
  gconstructorTuple = castOptic $ iso
    (\(M1 (K1 a1) :*: M1 (K1 a2)) -> (a1, a2))
    (\(b1, b2) -> M1 (K1 b1) :*: M1 (K1 b2))
  {-# INLINE gconstructorTuple #-}

-- | Only for a derived balanced representation.
instance
  ( r ~ (a1, a2, a3)
  , s ~ (b1, b2, b3)
  ) => GConstructorTuple
         (F m1 a1 :*: F m2 a2 :*: F m3 a3)
         (F m1 b1 :*: F m2 b2 :*: F m3 b3) r s where
  gconstructorTuple = castOptic $ iso
    (\(M1 (K1 a1) :*: M1 (K1 a2) :*: M1 (K1 a3)) -> (a1, a2, a3))
    (\(b1, b2, b3) -> M1 (K1 b1) :*: M1 (K1 b2) :*: M1 (K1 b3))
  {-# INLINE gconstructorTuple #-}

-- | Only for a derived balanced representation.
instance
  ( r ~ (a1, a2, a3, a4)
  , s ~ (b1, b2, b3, b4)
  ) => GConstructorTuple
         ((F m1 a1 :*: F m2 a2) :*: (F m3 a3 :*: F m4 a4))
         ((F m1 b1 :*: F m2 b2) :*: (F m3 b3 :*: F m4 b4)) r s where
  gconstructorTuple = castOptic $ iso
    (\((M1 (K1 a1) :*: M1 (K1 a2)) :*: (M1 (K1 a3) :*: M1 (K1 a4))) -> (a1, a2, a3, a4))
    (\(b1, b2, b3, b4) -> (M1 (K1 b1) :*: M1 (K1 b2)) :*: (M1 (K1 b3) :*: M1 (K1 b4)))
  {-# INLINE gconstructorTuple #-}

-- | Only for a derived balanced representation.
instance
  ( r ~ (a1, a2, a3, a4, a5)
  , s ~ (b1, b2, b3, b4, b5)
  ) => GConstructorTuple
         ((F m1 a1 :*: F m2 a2) :*: (F m3 a3 :*: F m4 a4 :*: F m5 a5))
         ((F m1 b1 :*: F m2 b2) :*: (F m3 b3 :*: F m4 b4 :*: F m5 b5)) r s where
  gconstructorTuple = castOptic $ iso
    (\((M1 (K1 a1) :*: M1 (K1 a2)) :*: (M1 (K1 a3) :*: M1 (K1 a4) :*: M1 (K1 a5))) ->
       (a1, a2, a3, a4, a5))
    (\(b1, b2, b3, b4, b5) ->
       (M1 (K1 b1) :*: M1 (K1 b2)) :*: (M1 (K1 b3) :*: M1 (K1 b4) :*: M1 (K1 b5)))
  {-# INLINE gconstructorTuple #-}

----------------------------------------
-- Types

class GPlateImpl g a where
  gplateImpl :: TraversalVL' (g x) a

instance GPlateImpl f a => GPlateImpl (M1 i c f) a where
  gplateImpl f (M1 x) = M1 <$> gplateImpl f x

instance (GPlateImpl f a, GPlateImpl g a) => GPlateImpl (f :+: g) a where
  gplateImpl f (L1 x) = L1 <$> gplateImpl f x
  gplateImpl f (R1 x) = R1 <$> gplateImpl f x

instance (GPlateImpl f a, GPlateImpl g a) => GPlateImpl (f :*: g) a where
  gplateImpl f (x :*: y) = (:*:) <$> gplateImpl f x <*> gplateImpl f y
  {-# INLINE gplateImpl #-}

-- | Matching type.
instance {-# OVERLAPPING #-} GPlateImpl (K1 i a) a where
  gplateImpl f (K1 a) = K1 <$> f a

-- | Recurse into the inner type if it has a 'Generic' instance.
instance GPlateInner (HasRep (Rep b)) b a => GPlateImpl (K1 i b) a where
  gplateImpl f (K1 b) = K1 <$> gplateInner @(HasRep (Rep b)) f b

instance GPlateImpl U1 a where
  gplateImpl _ = pure

instance GPlateImpl V1 a where
  gplateImpl _ = \case {}

instance GPlateImpl (URec b) a where
  gplateImpl _ = pure

class GPlateInner (repDefined :: RepDefined) s a where
  gplateInner :: TraversalVL' s a

instance (Generic s, GPlateImpl (Rep s) a) => GPlateInner 'RepDefined s a where
  gplateInner f = fmap to . gplateImpl f . from

instance {-# INCOHERENT #-} GPlateInner repNotDefined s a where
  gplateInner _ = pure

-- $setup
-- >>> import Optics.Core
