{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
-- |
-- Module: Optics.Label
-- Description: Overloaded labels as optics
--
-- Overloaded labels are a solution to Haskell's namespace problem for records.
-- The @-XOverloadedLabels@ extension allows a new expression syntax for labels,
-- a prefix @#@ sign followed by an identifier, e.g. @#foo@.  These expressions
-- can then be given an interpretation that depends on the type at which they
-- are used and the text of the label.
module Optics.Label
  ( -- * How to use labels as optics to make working with Haskell's records more convenient
    --
    -- ** The problem
    -- $problem

    -- ** The solution
    -- $solution

    -- ** The result
    -- $result

    -- * Sample usage
    -- $sampleUsage

    -- * Technical details

    -- ** 'LabelOptic' type class
    LabelOptic(..)
  , LabelOptic'

    -- ** Structure of 'LabelOptic' instances
    -- $instanceStructure

    -- ** Limitations arising from functional dependencies
    -- $fundepLimitations
  ) where

import Data.Type.Bool
import Data.Type.Equality
import GHC.Generics (Rep)
import GHC.OverloadedLabels
import GHC.TypeLits

import Optics.Internal.Generic
import Optics.Internal.Magic
import Optics.Internal.Optic

-- $sampleUsage
--
-- #usage#
--
-- An example showing how overloaded labels can be used as optics for fields of
-- types having a 'Generic' instance.
--
-- >>> :set -XDeriveGeneric
-- >>> :set -XDuplicateRecordFields
-- >>> :set -XOverloadedLabels
-- >>> import GHC.Generics (Generic)
-- >>> :{
-- data Human = Human
--   { name :: String
--   , age  :: Integer
--   , pets :: [Pet]
--   } deriving (Show, Generic)
-- data Pet
--   = Cat  { name :: String, age :: Int, lazy :: Bool }
--   | Fish { name :: String, age :: Int, lazy :: Bool }
--   deriving (Show, Generic)
-- :}
--
-- /Note:/ Generic deriving of optics works well on a moderate scale, but for
-- ubiquitous usage (and in production in general) we recommend generating them
-- with Template Haskell as it scales better in terms of compilation time. For
-- more details see @makeFieldLabelsNoPrefix@ from
-- <https://hackage.haskell.org/package/optics-th/docs/Optics-TH.html Optics.TH>
-- in the <https://hackage.haskell.org/package/optics-th optics-th> package.
--
-- Here is some test data:
--
-- >>> :{
-- peter :: Human
-- peter = Human { name = "Peter"
--               , age  = 13
--               , pets = [ Fish { name = "Goldie"
--                               , age  = 1
--                               , lazy = False
--                               }
--                        , Cat { name = "Loopy"
--                              , age  = 3
--                              , lazy = False
--                              }
--                        , Cat { name = "Sparky"
--                              , age  = 2
--                              , lazy = True
--                              }
--                        ]
--              }
-- :}
--
-- Now we can ask for Peter's name:
--
-- >>> peter ^. #name
-- "Peter"
--
-- or for names of his pets:
--
-- >>> peter ^.. #pets % folded % #name
-- ["Goldie","Loopy","Sparky"]
--
-- We can check whether any of his pets is lazy:
--
-- >>> orOf (#pets % folded % #lazy) peter
-- True
--
-- or how things might be be a year from now:
--
-- >>> peter & #age %~ (+1) & #pets % mapped % #age %~ (+1)
-- Human {name = "Peter", age = 14, pets = [Fish {name = "Goldie", age = 2, lazy = False},Cat {name = "Loopy", age = 4, lazy = False},Cat {name = "Sparky", age = 3, lazy = True}]}
--
-- Perhaps Peter is going on vacation and needs to leave his pets at home:
--
-- >>> peter & #pets .~ []
-- Human {name = "Peter", age = 13, pets = []}

-- $problem
--
-- Standard Haskell records are a common source of frustration amongst seasoned
-- Haskell programmers. Their main issues are:
--
-- (1) Inability to define multiple data types sharing field names in the same
--     module.
--
-- (2) Pollution of global namespace as every field accessor is also a top-level
--     function.
--
-- (3) Clunky update syntax, especially when nested fields get involved.
--
-- Over the years multiple language extensions were proposed and implemented to
-- alleviate these issues. We're quite close to having a reasonable solution
-- with the following trifecta:
--
-- - @<https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#extension-DuplicateRecordFields DuplicateRecordFields>@ - introduced in GHC 8.0.1, addresses (1)
--
-- - @<https://github.com/ghc-proposals/ghc-proposals/pull/160 NoFieldSelectors>@ - accepted GHC proposal, addresses (2)
--
-- - @<https://github.com/ghc-proposals/ghc-proposals/pull/282 RecordDotSyntax>@ - accepted GHC proposal, addresses (3)
--
-- It needs to be noted however that both @NoFieldSelectors@ and
-- @RecordDotSyntax@ are not yet implemented, with the latter depending on
-- adding @setField@ to @HasField@
-- (<https://gitlab.haskell.org/ghc/ghc/issues/16232 ghc/16232>), not yet
-- merged.
--
-- Is there no hope then for people who would like to work with records in a
-- reasonable way without waiting for these extensions? Not necessarily, as by
-- following a couple of simple patterns we can get pretty much the same (and
-- more) features with labels as optics, just with a slightly more verbose
-- syntax.

-- $solution
--
-- === Prefixless fields with @DuplicateRecordFields@
--
-- We necessarily want field names to be prefixless, i.e. @field@ to be a field
-- name and @#field@ to be an overloaded label that becomes an optic refering to
-- this field in the appropriate context.  With this approach we get working
-- autocompletion and jump-to-definition in editors supporting @ctags@/@etags@
-- in combination with @<https://hackage.haskell.org/package/hasktags hasktags>@,
-- both of which (especially the latter) are very important for developer's
-- productivity in real-world code bases.
--
-- Let's look at data types defined with this approach in mind:
--
-- @
-- {-\# LANGUAGE DuplicateRecordFields \#-}
--
-- import Data.Time
--
-- data User = User { id     :: Int
--                  , name   :: String
--                  , joined :: UTCTime
--                  , movies :: [Movie]
--                  }
--
-- data Movie = Movie { id          :: Int
--                    , name        :: String
--                    , releaseDate :: UTCTime
--                    }
-- @
--
-- Then appropriate 'LabelOptic' instances can be either written by hand,
-- seamlessly derived via generic representation (see the
-- <Optics-Label.html#usage Sample usage> section for more details)
-- or generated with Template Haskell functions
-- (defined in
-- <https://hackage.haskell.org/package/optics-th/docs/Optics-TH.html Optics.TH>
-- module from <https://hackage.haskell.org/package/optics-th optics-th>
-- package) with
--
-- @
-- makeFieldLabelsNoPrefix ''User
-- makeFieldLabelsNoPrefix ''Movie
-- @
--
-- For production software the recommended approach is generation with Template
-- Haskell as it scales well in terms of compilation time and provides the best
-- performance in general.
--
-- /Note:/ there exists a similar approach that involves prefixing field names
-- (either with the underscore or name of the data type) and generation of
-- lenses as ordinary functions so that @prefixField@ is the ordinary field name
-- and @field@ is the lens referencing it. The drawback of such solution is
-- inability to get working jump-to-definition for field names, which makes
-- navigation in unfamiliar code bases significantly harder, so it's not
-- recommended.
--
-- === Emulation of @NoFieldSelectors@
--
-- Prefixless fields (especially ones with common names such as @id@ or @name@)
-- leak into global namespace as accessor functions and can generate a lot of
-- name clashes. Before @NoFieldSelectors@ is available, this can be alleviated by
-- splitting modules defining types into two, namely:
--
-- (1) A private one that exports full type definitions, i.e. with their fields
--     and constructors.
--
-- (2) A public one that exports only constructors (or no constructors at all if
--     the data type in question is opaque).
--
-- There is no notion of private and public modules within a single cabal
-- target, but we can hint at it e.g. by naming the public module @T@ and
-- private @T.Internal@.
--
-- An example:
--
-- Private module:
--
-- @
-- {-\# LANGUAGE DataKinds \#-}
-- {-\# LANGUAGE FlexibleInstances \#-}
-- {-\# LANGUAGE MultiParamTypeClasses \#-}
-- {-\# LANGUAGE TemplateHaskell \#-}
-- {-\# LANGUAGE TypeFamilies \#-}
-- {-\# LANGUAGE UndecidableInstances \#-}
-- module User.Internal (User(..)) where
--
-- import Optics.TH
--
-- data User = User { id   :: Int
--                  , name :: String
--                  }
--
-- makeFieldLabelsNoPrefix ''User
--
-- ...
-- @
--
-- Public module:
--
-- @
-- module User (User(User)) where
--
-- import User.Internal
--
-- ...
-- @
--
-- Then, whenever we're dealing with a value of type @User@ and want to read or
-- modify its fields, we can use corresponding labels without having to import
-- @User.Internal@. Importing @User@ is enough because it provides appropriate
-- 'LabelOptic' instances through @User.Internal@ which enables labels to be
-- interpreted as optics in the appropriate context.
--
-- /Note:/ if you plan to completely hide (some of) the fields of a data type,
-- you need to skip defining the corresponding 'LabelOptic' instances for them
-- (in case you want fields to be read only, you can make the optic kind of the
-- coresponding 'LabelOptic' 'A_Getter' instead of 'A_Lens'). It's because
-- Haskell makes it impossible to selectively hide instances, so once a
-- 'LabelOptic' instance is defined, it'll always be possible to use a label
-- that desugars to its usage whenever a module with its definition is
-- (transitively) imported.
--
-- @
-- {-\# LANGUAGE OverloadedLabels #-}
--
-- import Optics
-- import User
--
-- greetUser :: User -> String
-- greetUser user = "Hello " ++ user ^. #name ++ "!"
--
-- addSurname :: String -> User -> User
-- addSurname surname user = user & #name %~ (++ " " ++ surname)
-- @
--
-- But what if we want to create a new @User@ with the record syntax? Importing
-- @User@ module is not sufficient since it doesn't export @User@'s
-- fields. However, if we import @User.Internal@ /fully qualified/ and make use
-- of the fact that field names used within the record syntax don't have to be
-- prefixed when @DisambiguateRecordFields@ language extension is enabled, it
-- works out:
--
-- @
-- {-\# LANGUAGE DisambiguateRecordFields \#-}
--
-- import User
-- import qualified User.Internal
--
-- newUser :: User
-- newUser = User { id   = 1     -- not User.Internal.id
--                , name = \"Ian\" -- not User.Internal.name
--                }
-- @
--
-- This way top-level field accessor functions stay in their own qualified
-- namespace and don't generate name clashes, yet they can be used without
-- prefix within the record syntax.

-- $result
--
-- When we follow the above conventions for data types in our application, we
-- get:
--
-- (1) Prefixless field names that don't pollute global namespace (with the
--     internal module qualification trick).
--
-- (2) Working tags based jump-to-definition for field names (as @field@ is the
--     ordinary field, whereas @#field@ is the lens referencing it).
--
-- (3) The full power of optics at our disposal, should we ever need it.

-- $instanceStructure
--
-- You might wonder why instances generated with Template Haskell have the
-- following form:
--
-- @
-- instance (k ~ A_Lens, a ~ [Pet], b ~ [Pet]) => LabelOptic "pets" k Human Human a b where
--   ...
-- @
--
-- instead of
--
-- @
-- instance LabelOptic "pets" A_Lens Human Human [Pet] [Pet] where
--   ...
-- @
--
-- The reason is that using the first form ensures that it is enough for GHC to
-- match on the instance if either @s@ or @t@ is known (as equality constraints
-- are solved after the instance matches), which not only makes type inference
-- better, but also allows it to generate better error messages.
--
-- >>> :set -XDataKinds
-- >>> :set -XFlexibleInstances
-- >>> :set -XMultiParamTypeClasses
-- >>> :set -XTypeFamilies
-- >>> :set -XUndecidableInstances
-- >>> :{
-- data Pet = Dog { name :: String }
--          | Cat { name :: String }
--   deriving Show
-- :}
--
-- >>> :{
-- data Human1 = Human1 { pets :: [Pet] }
--   deriving Show
-- instance LabelOptic "pets" A_Lens Human1 Human1 [Pet] [Pet] where
--   labelOptic = lensVL $ \f (Human1 pets) -> Human1 <$> f pets
-- :}
--
-- >>> :{
-- data Human2 = Human2 { pets :: [Pet] }
--  deriving Show
-- instance (k ~ A_Lens, a ~ [Pet], b ~ [Pet]) => LabelOptic "pets" k Human2 Human2 a b where
--   labelOptic = lensVL $ \f (Human2 pets) -> Human2 <$> f pets
-- :}
--
-- >>> let human1 = Human1 [Dog "Lucky"]
-- >>> let human2 = Human2 [Cat "Sleepy"]
--
-- Let's have a look how these two instance definitions differ.
--
-- >>> human1 & #pets .~ []
-- ...
-- ...No instance for LabelOptic "pets" ‘A_Lens’ ‘Human1’ ‘()’ ‘[Pet]’ ‘[a0]’
-- ...
--
-- >>> human2 & #pets .~ []
-- Human2 {pets = []}
--
-- That's because an empty list doesn't have a type @[Pet]@, it has a type @[r]@
-- and GHC doesn't have enough information to match on the instance we
-- provided. We'd need to either annotate the list:
--
-- >>> human1 & #pets .~ ([] :: [Pet])
-- Human1 {pets = []}
--
-- or the result type:
--
-- >>> human1 & #pets .~ [] :: Human1
-- Human1 {pets = []}
--
-- both of which are a nuisance.
--
-- Here are more examples of confusing error messages if the instance for
-- @LabelOptic "pets"@ is written without type equalities:
--
-- >>> human1 ^. #pets :: Char
-- ...
-- ...No instance for LabelOptic "pets" ‘k0’ ‘Human1’ ‘Human1’ ‘Char’ ‘Char’
-- ...
--
-- >>> human1 & #pets .~ 'x'
-- ...
-- ...No instance for LabelOptic "pets" ‘k0’ ‘Human1’ ‘Human1’ ‘a0’ ‘Char’
-- ...
--
-- >>> let pets = #pets :: Iso' Human1 [Pet]
-- ...
-- ...No instance for LabelOptic "pets" ‘An_Iso’ ‘Human1’ ‘Human1’ ‘[Pet]’ ‘[Pet]’
-- ...
--
-- If we use the second form, error messages become much more accurate:
--
-- >>> human2 ^. #pets :: Char
-- ...
-- ...Couldn't match type ‘Char’ with ‘[Pet]’
-- ...  arising from the overloaded label ‘#pets’
-- ...
--
-- >>> human2 & #pets .~ 'x'
-- ...
-- ...Couldn't match type ‘Char’ with ‘[Pet]’
-- ...  arising from the overloaded label ‘#pets’
-- ...
--
-- >>> let pets = #pets :: Iso' Human2 [Pet]
-- ...
-- ...Couldn't match type ‘An_Iso’ with ‘A_Lens’
-- ...  arising from the overloaded label ‘#pets’
-- ...

-- $fundepLimitations #limitations#
--
-- 'LabelOptic' uses the following functional dependencies to guarantee good
-- type inference:
--
-- 1. @name s -> k a@ (the optic for the field @name@ in @s@ is of type @k@ and
-- focuses on @a@)
--
-- 2. @name t -> k b@ (the optic for the field @name@ in @t@ is of type @k@ and
-- focuses on @b@)
--
-- 3. @name s b -> t@ (replacing the field @name@ in @s@ with @b@ yields @t@)
--
-- 4. @name t a -> s@ (replacing the field @name@ in @t@ with @a@ yields @s@)
--
-- Dependencies (1) and (2) ensure that when we compose two optics, the middle
-- type is unambiguous. The consequence is that it's not possible to create
-- label optics with @a@ or @b@ referencing type variables not referenced in @s@
-- or @t@, i.e. getters for fields of rank 2 type or reviews for constructors
-- with existentially quantified types inside.
--
-- Dependencies (3) and (4) ensure that when we perform a chain of updates, the
-- middle type is unambiguous. The consequence is that it's not possible to
-- define label optics that:
--
-- - Modify phantom type parameters of type @s@ or @t@.
--
-- - Modify type parameters of type @s@ or @t@ if @a@ or @b@ contain ambiguous
--   applications of type families to these type parameters.

----------------------------------------
-- Definitions

-- | Support for overloaded labels as optics. An overloaded label @#foo@ can be
-- used as an optic if there is an instance of @'LabelOptic' "foo" k s t a b@ or
-- both @s@ and @t@ have a 'Generic' instance.
class LabelOptic (name :: Symbol) k s t a b | name s -> k a
                                            , name t -> k b
                                            , name s b -> t
                                            , name t a -> s where
  -- | Used to interpret overloaded label syntax.  An overloaded label @#foo@
  -- corresponds to @'labelOptic' \@"foo"@.
  labelOptic :: Optic k NoIx s t a b

-- | Type synonym for a type-preserving optic as overloaded label.
type LabelOptic' name k s a = LabelOptic name k s s a a

data Void0
-- | If for an overloaded label @#label@ there is no instance starting with
-- @LabelOptic "label"@ in scope, using it in the context of optics makes GHC
-- immediately pick the overlappable instance defined below (since no other
-- instance could match). If at this point GHC has no information about @s@ or
-- @t@, it ends up picking incoherent instance of 'GenericLabelOptic' defined
-- below. Prevent that (if only to be able to inspect most polymorphic types of
-- @#foo % #bar@ or @view #foo@ in GHCi) by defining a dummy instance that
-- matches all names, thus postponing instance resolution until @s@ or @t@ is
-- known.
instance
  ( k ~ An_Iso, a ~ Void0, b ~ Void0
  ) => LabelOptic name k Void0 Void0 a b where
  labelOptic = Optic id

-- | If no instance matches, try to use 'Generic' machinery for field access.
instance {-# OVERLAPPABLE #-}
  ( s `HasShapeOf` t
  , t `HasShapeOf` s
  , GeneralLabelOptic (BothHaveRep (Rep s) (Rep t)) name k s t a b
  , LiftCoverageCondition name k s t a b
  ) => LabelOptic name k s t a b where
  labelOptic = generalLabelOptic @(BothHaveRep (Rep s) (Rep t)) @name

----------------------------------------

-- | Implements fallback behaviour for 'Generic' based field access in case
-- there is no explicit 'LabelOptic' instance.
--
-- To support this, the first parameter will be instantiated to 'RepDefined' if
-- at least one of @s@ or @t@ has a 'Generic' instance.
class GeneralLabelOptic (repDefined :: RepDefined) (name :: Symbol) k s t a b where
  -- | Used to interpret overloaded label syntax in the absence of an explicit
  -- 'LabelOptic' instance.
  generalLabelOptic :: Optic k NoIx s t a b

-- | If @s@ or @t@ has a 'Generic' instance, use generics-based data access.
instance
  ( k ~ If (CmpSymbol "_@" name == 'LT && CmpSymbol "_[" name == 'GT)
           A_Prism
           A_Lens
  , GenericOptic name k s t a b
  ) => GeneralLabelOptic 'RepDefined name k s t a b where
  generalLabelOptic = genericOptic @name

-- | Otherwise report an error.
instance {-# INCOHERENT #-}
  ( TypeError
    ('Text "No instance for LabelOptic " ':<>: 'ShowType name
     ':<>: 'Text " " ':<>: QuoteType k
     ':<>: 'Text " " ':<>: QuoteType s
     ':<>: 'Text " " ':<>: QuoteType t
     ':<>: 'Text " " ':<>: QuoteType a
     ':<>: 'Text " " ':<>: QuoteType b
     ':$$: 'Text "Possible solutions:"
     ':$$: 'Text "- Check and correct spelling of the label"
     ':$$: 'Text "- Define the LabelOptic instance by hand or via Template Haskell"
     ':$$: 'Text "- Derive a Generic instance for " ':<>: QuoteType s
    )
  ) => GeneralLabelOptic repNotDefined name k s t a b where
  generalLabelOptic = error "unreachable"

----------------------------------------

class GenericOptic name k s t a b where
  genericOptic :: Optic k NoIx s t a b

instance
  ( GFieldImpl name s t a b
  ) => GenericOptic name A_Lens s t a b where
  genericOptic = gfieldImpl @name

instance
  ( GConstructorImpl name s t a b
  , _name ~ AppendSymbol "_" name
  ) => GenericOptic _name A_Prism s t a b where
  genericOptic = gconstructorImpl @name

----------------------------------------

instance
  (LabelOptic name k s t a b, is ~ NoIx
  ) => IsLabel name (Optic k is s t a b) where
  fromLabel = labelOptic @name

-- $setup
-- >>> import Optics.Core
