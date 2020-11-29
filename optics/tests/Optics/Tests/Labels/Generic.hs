{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin=Test.Inspection.Plugin -dsuppress-all #-}
module Optics.Tests.Labels.Generic where

import Data.Ord
import GHC.Generics (Generic)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Inspection

import Optics
import Optics.Tests.Utils

data Mammal
  = Dog { name :: String, age :: Int, lazy :: Bool }
  | Cat { name :: String, age :: Int, lazy :: Bool }
  deriving (Show, Generic)

data Fish
  = GoldFish { name :: String }
  | Herring  { name :: String }
  deriving (Show, Generic)

data Human a = Human
  { name :: String
  , age  :: Int
  , fish :: Fish
  , pets :: [a]
  }
  deriving (Show, Generic)

----------------------------------------

genericLabelsTests :: TestTree
genericLabelsTests = testGroup "Labels via Generic"
  [
    testCase "view #name s = name s" $
    assertSuccess $(inspectTest $ 'label1lhs ==- 'label1rhs)
  , testCase "set #pets s b = s { pets = b }" $
    assertSuccess $(inspectTest $ 'label2lhs ==- 'label2rhs)
  , testCase "view (#fish % #name) s = name (fish s)" $
    assertSuccess $(inspectTest $ 'label3lhs ==- 'label3rhs)
  , testCase "set (#fish % #name) b s = s { fish = ... }" $
    assertSuccess $(inspectTest $ 'label4lhs ==- 'label4rhs)
  , testCase "set (#pets % traversed % #name) b s = s { pets = ... }" $
    assertSuccess $(inspectTest $ 'label5lhs ==- 'label5rhs)
  , testCase "multiple set with labels = multiple set with record syntax" $
    assertSuccess $(inspectTest $ 'label6lhs ==- 'label6rhs)
  , testCase "optimized petNames (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'petNames)
  , testCase "optimized otherHuman (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'otherHuman)
  , testCase "optimized humanWithFish (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'humanWithFish)
  , testCase "optimized howManyGoldFish (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'howManyGoldFish)
  , testCase "optimized hasLazyPets (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'hasLazyPets)
  , testCase "optimized yearLater (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'yearLater)
  , testCase "optimized oldestPet (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'oldestPet)
  , testCase "optimized luckyDog (generics)" $
    assertSuccess $(inspectTest $ hasNoGenericRep 'luckyDog)
  ]

label1lhs, label1rhs :: forall a. Human a -> String
label1lhs s = view #name s
label1rhs s = name (s :: Human a)

label2lhs, label2rhs :: Human a -> [b] -> Human b
label2lhs s b = set #pets b s
label2rhs s b = s { pets = b }

label3lhs, label3rhs :: Human a -> String
label3lhs s = view (#fish % #name) s
label3rhs s = name (fish s :: Fish)

label4lhs, label4rhs :: Human a -> String -> Human a
label4lhs s b = set (#fish % #name) b s
label4rhs s b = s { fish = (fish s) { name = b } }

label5lhs, label5rhs :: Human Mammal -> Bool -> Human Mammal
label5lhs s b = set (#pets % traversed % #lazy) b s
label5rhs s b = s { pets = map (\p -> p { lazy = b }) (pets s) }

label6lhs, label6rhs :: Human a -> String -> Int -> String -> [b] -> Human b
label6lhs s name_ age_ fishName_ pets_ = s
  & #name              .~ name_
  & #age               .~ age_
  & #fish % #_GoldFish .~ fishName_
  & #pets              .~ pets_
label6rhs s name_ age_ fishName_ pets_ = s
  { name = name_
  , age  = age_
  , fish = case fish s of
      GoldFish{} -> GoldFish fishName_
      herring    -> herring
  , pets = pets_
  }

----------------------------------------
-- Basic data manipulation

human :: Human Mammal
human = Human
  { name = "Andrzej"
  , age = 30
  , fish = GoldFish "Goldie"
  , pets = [Dog "Rocky" 3 False, Cat "Pickle" 4 True, Cat "Max" 1 False]
  }

petNames :: [String]
petNames = toListOf (#pets % folded % #name) human

otherHuman :: Human a
otherHuman = human & set #name "Peter"
                   & set #pets []
                   & set #age  41

humanWithFish :: Human Fish
humanWithFish = set #pets [GoldFish "Goldie", GoldFish "Slick", Herring "See"] human

howManyGoldFish :: Int
howManyGoldFish = lengthOf (#pets % folded % #_GoldFish) humanWithFish

hasLazyPets :: Bool
hasLazyPets = orOf (#pets % folded % #lazy) human

yearLater :: Human Mammal
yearLater = human & #age %~ (+1)
                  & #pets % mapped % #age %~ (+1)

oldestPet :: Maybe Mammal
oldestPet = maximumByOf (#pets % folded) (comparing $ view #age) human

luckyDog :: Human Mammal
luckyDog = human & set (#pets % mapped % #_Dog % _1) "Lucky"