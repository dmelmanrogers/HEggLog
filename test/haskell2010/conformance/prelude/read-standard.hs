module Main where

readIntValue :: Int
readIntValue = read "123"

readNegativeIntValue :: Int
readNegativeIntValue = read "-45"

readBoolValue :: Bool
readBoolValue = read "True"

readCharValue :: Char
readCharValue = read "'Z'"

readStringValue :: String
readStringValue = read "\"hi\""

readListValue :: [Int]
readListValue = read "[1,2,3]"

readsBoolBoundary :: [(Bool, String)]
readsBoolBoundary = reads "Truex"

readListStringValue :: [(String, String)]
readListStringValue = readList "\"ok\"!"

readParenIntValue :: [(Int, String)]
readParenIntValue = readParen True (readsPrec 0) "(7)!"

lexTokenValue :: [(String, String)]
lexTokenValue = lex "Foo 1"

orderingValue :: [(Ordering, String)]
orderingValue = reads "GT!"

unitValue :: [((), String)]
unitValue = reads "()!"

main :: IO ()
main = do
  putStrLn (show readIntValue)
  putStrLn (show readNegativeIntValue)
  putStrLn (show readBoolValue)
  putStrLn (show readCharValue)
  putStrLn readStringValue
  putStrLn (show readListValue)
  putStrLn (show (length readsBoolBoundary))
  putStrLn (fst (head readListStringValue))
  putStrLn (show (fst (head readParenIntValue)))
  putStrLn (fst (head lexTokenValue))
  case fst (head orderingValue) of
    GT -> putStrLn "GT"
    EQ -> putStrLn "EQ"
    LT -> putStrLn "LT"
  putStrLn (show (length unitValue))
  return ()
