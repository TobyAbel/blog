-- This file implements a tiny templating engine inspired by Moustache. A
-- context for applying templates is a subset of json that features strings,
-- lists, and maps. A template is a string where things inside {{moustaches}}
-- have special meaning:
--
--  * Conditionals: "{{if <cond>}} inner {{end}}" expands to " inner " if the
--    key <cond> is present in the context, and it does not equal the string
--    "false". This makes it possible to switch "foo: true" to "foo: false"
--    instead of having to remove the key entirely.
--
--  * Loops: "{{foreach <list>}} inner {{end}}" expands to an expansion of
--    " inner " for every element of <list>. The context for the inner expansion
--    is the list element. (So list must be a list of maps [TODO].)
--
--  * Variables: "{{<var>}}" expands to the value of <var> if that is a string.

import           Control.Monad (join)
import qualified Data.Map as M

data Token = Outer String | Inner String

-- Splits a string into things inside and outside of moustaches.
tokenize :: String -> [Token]
tokenize str = next str (Outer "") []
  where next :: String -> Token -> [Token] -> [Token]
        next             []         token tokens = tokens ++ [token]
        next ('{':'{':more) (Outer outer) tokens = next more (Inner "") (tokens ++ [Outer outer])
        next (      c:more) (Outer outer) tokens = next more (Outer (outer ++ [c])) tokens
        next ('}':'}':more) (Inner inner) tokens = next more (Outer "") (tokens ++ [Inner inner])
        next (      c:more) (Inner inner) tokens = next more (Inner (inner ++ [c])) tokens

data Fragment = Loop String
              | Conditional String
              | End
              | Variable String
              | Raw String
  deriving (Show) -- TODO This is for debugging only, remove.

-- Converts a string into fragments that can be fed into the interpreter.
parse :: String -> [Fragment]
parse = fmap toFragment . tokenize
  where toFragment (Outer str) = Raw str
        toFragment (Inner str) = case break (== ' ') str of
          ("foreach", list) -> Loop $ tail list
          ("if", condition) -> Conditional $ tail condition
          ("end", "")       -> End
          (variable, _)     -> Variable variable

data Context = StringContext String
             | MapContext (M.Map String Context)
             | ListContext [Context] -- TODO: This is useless indirection, make it [M.Map String Context] instead?

-- Applies the template (fragments) with given context until an end fragment is
-- encountered, at which point the currint string and the remaining fragments
-- are returned.
applyBlock :: [Fragment] -> Context -> (String, [Fragment])
applyBlock fragments context = next fragments ""
  where lookup name = case context of
          MapContext map -> M.lookup name map
          _              -> Nothing
        expand variable = case lookup variable of
          Just (StringContext str) -> str
          Just (ListContext _)     -> variable ++ " is a list"
          Just (MapContext _)      -> variable ++ " is a map"
          Nothing                  -> "undefined"
        isTrue condition = case lookup condition of
          Just (StringContext "false") -> False
          Just _                       -> True -- TODO: should an empty list or empty map be false?
          Nothing                      -> False -- Or should only "true" be true?
        getList name = case lookup name of
          Just (ListContext list) -> list
          _                       -> []
        next :: [Fragment] -> String -> (String, [Fragment])
        next              [] str = (str, [])
        next (fragment:more) str = case fragment of
          End               -> (str, more)
          Raw contents      -> next more (str ++ contents)
          Variable variable -> next more (str ++ expand variable)
          Conditional cond  -> next continue $ if (isTrue cond) then str ++ inner else str
            where (inner, continue) = applyBlock more context
          Loop list         -> next continue $ str ++ inner
            where inner         = join $ fmap (\ctx -> fst $ applyBlock more ctx) $ getList list
                  (_, continue) = applyBlock more context

apply :: [Fragment] -> Context -> String
apply fragments context = fst $ applyBlock fragments context