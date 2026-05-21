module InstanceProvider () where

import InstanceClass (Measure(..))
import InstanceType (Box(..))

instance Measure Box where
  measure (Box n) = n + 1
