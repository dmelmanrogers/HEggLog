module Main where

same :: Char -> Char -> Bool
same x y = x == y

different :: Char -> Char -> Bool
different x y = x /= y

main =
  case 'h' of
    'h' -> if same 'a' 'a' && different 'a' 'b' then 1 else 0
    _ -> 0
