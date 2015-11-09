-- Copyright 2015 Ruud van Asseldonk
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License version 3. See
-- the licence file in the root of the repository.

module Post ( Post
            , body
            , context
            , date
            , longDate
            , parse
            , relatedContext
            , shortDate
            , selectRelated
            , slug
            , title
            , url
            , year ) where

import qualified Data.Map as M
import           Data.Maybe (fromMaybe)
import qualified Data.Set as S
import           Data.Time.Format
import           Data.Time.Calendar (Day, showGregorian, toGregorian)
import           GHC.Exts (sortWith)
import           Text.Pandoc

import qualified Html
import qualified Template as T

-- Front matter consists of key value pairs, both of type string.
-- There is no fancy YAML here.
type FrontMatter = M.Map String String

-- Strips off and parses front matter from the string. Front matter is
-- delimited by triple dashes. Keys are anything before ": ", the value
-- is what comes after that. Ignores first line assuming it is "---".
extractFrontMatter :: String -> (FrontMatter, String)
extractFrontMatter = parseFM M.empty . drop 1 . lines
  where parseFM fm ("---":body) = (fm, unlines body)
        parseFM fm (line:more)  = parseFM (M.insert key value fm) more
          where (key, delimValue) = break (== ':') line
                value = drop 2 delimValue -- Drop the colon and space.

data Post = Post { title     :: String
                 , header    :: String
                 , subheader :: Maybe String
                 , part      :: Maybe Int
                 , date      :: Day
                 , slug      :: String
                 , synopsis  :: String
                 , body      :: String } deriving (Show) -- TODO: This is for debugging only, remove.

-- Returns the post date, formatted like "17 April, 2015".
longDate :: Post -> String
longDate = formatTime defaultTimeLocale "%e %B, %Y" . date

-- Returns the post date, formatted like "2015-04-17".
shortDate :: Post -> String
shortDate = showGregorian . date

-- Returns the year in which the post was published.
year :: Post -> Integer
year post = y where (y, m, d) = toGregorian $ date post

-- Returns the canonical absolute url for a particular post.
url :: Post -> String
url post = "/" ++ datePath ++ "/" ++ (slug post)
  where datePath = formatTime defaultTimeLocale "%Y/%m/%d" $ date post

-- Returns whether post has code in it that requires a monospace font.
usesMonoFont :: Post -> Bool
usesMonoFont = not . null . Html.getCode . body

-- Converts an integer to a Roman numeral (nothing fancy, works for 1-9).
toRoman :: Int -> String
toRoman i = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"] !! (i - 1)

-- Returns the template expansion context for the post.
context :: Post -> T.Context
context p = fmap T.StringValue ctx
  where ctx       = M.union fields (M.mapMaybe id optFields)
        fields    = M.fromList [ ("title", title p)
                               , ("header", header p)
                               , ("short-date", shortDate p)
                               , ("long-date", longDate p)
                               , ("url", url p)
                               , ("synopsis", synopsis p)
                               , ("content", body p) ]
        optFields = M.fromList [ ("subheader", subheader p)
                               , ("part", fmap toRoman $ part p)
                               , ("mono-font", monoFontField) ]
        monoFontField = if usesMonoFont p then Just "true" else Nothing

-- Given a slug and the contents of the post file (markdown with front matter),
-- renders the body to html and parses the metadata.
parse :: String -> String -> Post
parse slug contents = Post {
  title     = frontMatter M.! "title",
  header    = fromMaybe (frontMatter M.! "title") $ M.lookup "header" frontMatter,
  subheader = M.lookup "subheader" frontMatter,
  part      = fmap read $ M.lookup "part" frontMatter,
  date      = parseTimeOrError True defaultTimeLocale "%F" (frontMatter M.! "date"),
  slug      = slug,
  synopsis  = fromMaybe "TODO: Write synopsis." $ M.lookup "synopsis" frontMatter,
  body      = renderMarkdown bodyContents
} where (frontMatter, bodyContents) = extractFrontMatter contents

-- Renders markdown to html using Pandoc with my settings.
renderMarkdown :: String -> String
renderMarkdown md = case fmap (writeHtmlString wopt) (readMarkdown ropt md) of
  Right result -> result
  Left  _      -> "Failed to parse markdown."
  -- Enable inline LaTeX between dollars, and enable backtick code blocks.
  -- For output, enable syntax highlighting of code and write math as MathML.
  where ropt = def { readerExtensions     = S.insert Ext_tex_math_dollars $
                                            S.insert Ext_backtick_code_blocks $
                                            def }
        wopt = def { writerHighlight      = True
                   , writerHTMLMathMethod = MathML Nothing }

-- Related content for a post, for the further reading section in the footer.
data RelatedContent = Further Post
                    | Series [Post]
                    deriving (Show) -- TODO: this is for debugging only, remove.

-- Returns the template expansion context for related content.
relatedContext :: RelatedContent -> T.Context
relatedContext related = case related of
  Further post -> T.nestContext "further" $ context post
  Series posts -> M.singleton "series" $ T.ListValue $ fmap context posts

-- Takes an (unordered) list of posts and produces a list of posts together with
-- related content for that post.
selectRelated :: [Post] -> [(Post, RelatedContent)]
selectRelated posts = fmap nextElsePrev prevPostNext
  where -- Create chronological triples of (previous post, post, next post).
        chronological = sortWith date posts
        prevPosts     = Nothing : (fmap Just chronological)
        nextPosts     = (drop 1 $ fmap Just chronological) ++ [Nothing]
        prevPostNext  = zip3 prevPosts chronological nextPosts

        -- Select the next post as "Further" content if there is one, otherwise
        -- take the previous post (which is assumed to exist in that case).
        nextElsePrev x = case x of
          (_, post, Just next) -> (post, Further next)
          (Just prev, post, _) -> (post, Further prev)
