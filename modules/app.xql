xquery version "3.0";

module namespace app="http://exist-db.org/apps/wolfslaw/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://exist-db.org/apps/wolfslaw/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare namespace functx = "http://www.functx.com";
declare function functx:contains-any-of
  ( $arg as xs:string? ,
    $searchStrings as xs:string* )  as xs:boolean {

   some $searchString in $searchStrings
   satisfies contains($arg,$searchString)
 } ;
 
 declare
    %templates:wrap
    %templates:default("target-fields", "text")
    %templates:default("target-texts", "all")
    %templates:default("mode", "any")
function app:search($node as node(), $model as map(*), $query as xs:string?, $target-fields as xs:string+, $target-texts as xs:string+, $mode as xs:string) {
    let $query := app:create-query()
    return
        if (empty($query) or $query = "") then
            let $cached := session:get-attribute("wolfslaw.cached-data")
            return
                if (empty($cached)) then
                    <p>No search term was specified and no search is cached.</p>
                else
                    map {
                        "results" := $cached
                    }
        else 
            let $target-texts := request:get-parameter('target-texts', 'all')
            let $context := 
                if ($target-texts = 'all')
                then collection($config:data-root)/tei:TEI
                else collection($config:data-root)//tei:TEI[@xml:id = $target-texts] 
            let $results := 
                for $target-field in $target-fields 
                return
                    switch ($target-field)
                        case "title" return
                            $context//tei:div[ft:query(tei:head, $query)]
                        default (:text:) return
                            $context//tei:div[ft:query(., $query)][not(tei:div)]
            return
                let $report := request:get-parameter("report", "no")
                let $report := 
                    if ($report eq 'yes')
                    then app:report($query, $context, $target-texts, $target-fields)
                    else ()
                let $sorted :=
                    for $result in $results
                    order by ft:score($result) descending
                    return
                        $result
                let $cached := session:set-attribute("wolfslaw.cached-data", $sorted)
                return
                    map {
                        "results" := $sorted,
                        "report" := $report
                    }
    };


(:~
    Helper function to create a Lucene query with XML syntax from the user input
:)

declare function app:create-query() {
    let $query-string := request:get-parameter("query", ())
    let $query-string := normalize-space($query-string)
    (:TODO: integrate mode!:)
    let $mode := request:get-parameter("mode", "any")
    let $luceneParse := local:parse-lucene($query-string)
    let $luceneXML := util:parse($luceneParse)
    return local:lucene2xml($luceneXML/node())

    (:    <query>
        {
            if ($mode eq 'any') then
                for $term in tokenize($query-string, '\s')
                return
                    if (functx:contains-any-of($term, ('?', '*')))
                    then <wildcard occur="should">{$term}</wildcard>
                    else <term occur="should">{$term}</term>
            else if ($mode eq 'all') then
                <bool>
                {
                    for $term in tokenize($query-string, '\s')
                    return
                        if (functx:contains-any-of($term, ('?', '*')))
                        then <wildcard occur="must">{$term}</wildcard>
                        else <term occur="must">{$term}</term>
                }
                </bool>
            else if ($mode eq 'phrase') then
                <phrase>{$query-string}</phrase>
            else
                <near slop="5" ordered="no">
                {
                    for $term in tokenize($query-string, '\s')
                    return
                        <term>{$term}</term>
                }
                </near>
        }
        </query>:)
};

declare
    %templates:default('start', 1)
function app:navigate($node as node(), $model as map(*), $start as xs:int) {
    <ul class="pagination">
        {
            if ($start = 1) then
                <li class="disabled">
                    <a>Previous Page</a>
                </li>
            else 
                <li>
                    <a href="?start={max( ($start - 20, 1 ) ) }">Previous Page</a>
                </li>
        }
        {
            for $i in 1 to xs:integer(ceiling(count($model("results")) div 20))
            return
                if ($i = ceiling($start div 20)) then
                    <li class="active"><a href="?start={max( (($i - 1) * 20 + 1, 1) )}">{$i}</a></li>
                else
                    <li><a href="?start={max( (($i - 1) * 20 + 1, 1)) }">{$i}</a></li>
        }
        {
            if ($start + 20 < count($model("results"))) then
                <li>
                    <a href="?start={$start + 20}">Next Page</a>
                </li>
            else
                <li class="disabled">
                    <a>Next Page</a>
                </li>
        }
    </ul>
};

declare
    %templates:wrap
    %templates:default("start", 1)
function app:retrieve-page($node as node(), $model as map(*), $start as xs:int) {
    <div class="col-md-12">
    <table class="table table-striped">
    {
        (:for $result in subsequence($model("results"), $start, 20)
        return
            <tr>
                <td>{$result/ancestor::tei:TEI//tei:titleStmt/tei:title[@type="short"]/text()}</td>
                <td>{ app:process(util:expand($result)) }</td>
            </tr>:)
        
        for $result in subsequence($model("results"), $start, 20)
        let $shortTitle := $result/ancestor::tei:TEI//tei:titleStmt/tei:title[@type="short"]/text()
        let $id := $result/ancestor::tei:TEI/@xml:id/string()
        return
            <tr>
                <td>
                    <a class="btn btn-default" href="view.html?id={$id}#{generate-id($result)}">{$shortTitle}</a>
                </td>
                <td>{ app:process(util:expand($result)) }</td>
            </tr>
    }
    </table>
    </div>
};

declare
    %templates:wrap
function app:result-count($node as node(), $model as map(*)) {
    let $hit-count := count($model("results"))
    let $class := 
        if ($hit-count) 
        then 'col-md-12 alert alert-success' 
        else 'col-md-12 alert alert-danger' 
    return
        <div class="{$class}">Found <b class="btn btn-default" data-template="app:result-count">{$hit-count}</b> hits. {$model("report")}</div>
};

declare 
    %templates:wrap
function app:table-of-contents($node as node(), $model as map(*)) {
    for $law in collection($config:data-root)//tei:TEI
    let $title := $law//tei:titleStmt/tei:title[not(@type)]/text()
    let $short-title := $law//tei:titleStmt/tei:title[@type="short"]/text()
    let $id := $law/@xml:id/string()
    return
    <tr>
        <td><input type="checkbox" name="target-texts" value="{$id}"></input></td>
        <td>{$short-title}</td>
        <td><a href="view.html?id={$id}">{$title}</a></td>
    </tr>
};

declare
    %templates:wrap
function app:load($node as node(), $model as map(*), $id as xs:string) {
    let $law := collection($config:data-root)/tei:TEI[@xml:id eq $id]
    return
        map {
            "law" := $law
        }
};

declare
    %templates:wrap
function app:title($node as node(), $model as map(*)) {
    let $titleStmt := $model("law")//tei:fileDesc/tei:titleStmt
    let $title := $titleStmt/tei:title[not(@type)]
    return
        $title/text()
};

declare
    %templates:wrap
function app:title-short($node as node(), $model as map(*)) {
    let $titleStmt := $model("law")//tei:fileDesc/tei:titleStmt
    let $short := $titleStmt/tei:title[@type = "short"]
    return
        $short/text()
};

declare
    %templates:wrap
function app:view($node as node(), $model as map(*)) {
    app:process($model("law")/tei:text/tei:body)
};

declare
    %templates:wrap
function app:current-law($node as node(), $model as map(*)) {
    attribute value { $model("law")/@xml:id }
};

declare function app:get-hits($query-string as xs:string, $context as element()*) {    
        $context[ft:query(., $query-string)]
};

declare function app:serialize-list($sequence as item()*) as item()* {       
    let $sequence-count := count($sequence)
    return
        if ($sequence-count eq 1)
            then $sequence
            else
                if ($sequence-count eq 2)
                then 
                    let $first := subsequence($sequence, 1, $sequence-count - 1)
                    let $last := $sequence[$sequence-count]
                    return
                        ($first, ' and ', $last)
                (:NB: Is it worthwhile doing this for more than two terms?:)
                else (string-join(subsequence($sequence, 1, $sequence-count - 1), ', '),', and ', $sequence[$sequence-count])
};

declare function app:report($query as element(), $context as element()*, $target-texts as xs:string+, $target-fields as xs:string+) {
    (:The suggestions look smart, but do not offer much help in practice; an understandable description of the search result is of more use.:)
    (:If the suggestions are to be of some help (à la Google: "Did you mean?") a fuzzy search would have to be made, 
    ordered in descending frequency, but even this would not be intelligent enough.:)
    (:TODO: Something like the following should be output:
    You searched for x, y and z in the fields a and b in the texts k, l and m.
    x had 23 hits and y had 4 hits, but z did not have any hits.
    Do you wish to have your partial search results displayed or do you wish to revise your search?:)
    (:Sometimes users may perform "any" searches because they are unsure about which search terms occur and they just enter all possibilities; 
    in such cases they probably want the search results to be displayed.:)
    let $query-strings := ($query//term/text(), $query//wildcard/text())
    let $query-strings := 
        if ($query-strings) 
        then $query-strings 
        else tokenize($query//phrase/text(), ' ')
    let $query-result :=
        <result>{
            for $query-string in $query-strings
            return
                let $result := $context[ft:query(., $query-string)]
                return 
                    if ($result)
                    then <span class="present" n="{$result[1]/@freq/string()}">{$query-string}</span>
                    else <span class="absent">{$query-string}</span>
        }</result>        
    let $present := $query-result//span[@class eq 'present']
    let $present-list :=
        for $item in $present
        return <item>{$item} had {$item/@n/string()} hits</item> 
    let $present-list := app:serialize-list($present-list)
    let $absent := $query-result//span[@class eq 'absent']
    let $absent-count := count($absent)
    let $absent-list := 
        if ($absent-count)
        then app:serialize-list($absent)
        else ()
    let $search-url:= request:get-url()
    let $query-string:= request:get-query-string()
    let $overide-url := concat($search-url, '?', $query-string, '&amp;override=true')
    let $choices := 
        <div class="alt">Do you wish to
            <a onclick="window.history.back()"> revise your search</a> or 
            <a href="index.html">perform a new search</a>?
        </div>
    return 
        if ($present and $absent)    
        then 
            <div class="query-result">
                <div class="hits"><span class="query-term">{$present-list}</span>, but <span class="query-term">{$absent-list}</span> did not have any hits.</div> 
                {$choices}
            </div>
        else
            if ($present)
            then
                <div class="query-result">
                    <div class="hits"><span class="query-term">{$present-list}</span>.</div> 
                    {$choices}
                </div>
            else
                <div class="query-result">
                    <div class="hits"><span class="query-term">{$absent-list}</span> did not have any hits.</div>
                    {$choices}
                </div>
        (:,
        for $absent in $query-result//span[@class eq 'absent']
        return    
            <ul class="list-group">
            {
                let $words := app:get-hits(substring($absent, 1, 2), $target-texts, $target-fields)
                let $before := $words[@name < $absent]
                let $after := $words[@name > $absent]
                let $merged := (
                    subsequence($before, count($before) - 10),
                    subsequence($after, 1, 10)
                )
                for $absent in $merged
                return
                    <li class="list-group-item">
                    <a href="?query={$absent/@name}">{$absent/@name/string()}</a> <span class="badge">{$absent/@freq/string()}</span>
                    </li>
            }
            </ul>:)
};

declare function app:process($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
            case text() return
                $node
            case element(exist:match) return
                <mark>{$node/text()}</mark>
            case element(tei:body) return
                app:process($node/*)
            case element(tei:div) return
                <div id="{generate-id($node)}">
                    {app:process($node/node())}
                </div>
            case element(tei:head) return
                let $level := count($node/ancestor::tei:div)
                return
                    element { "h" || $level } {
                        app:process($node/node())
                    }
            case element(tei:p) return
                <p>{app:process($node/node())}</p>
            case element(tei:list) return
                <ol type="{if (matches($node/tei:item[1]/@n, '^\d')) then '1' else 'a'}">
                    {app:process($node/node())}
                </ol>
            case element(tei:item) return
                <li>{app:process($node/node())}</li>
            case element(exist:match) return
                <span class="hi">{$node/node()}</span>
            case element() return
                app:process($node/node())
            default return
                $node
};

(:@author: Ron Van den Branden, https://rvdb.wordpress.com/2010/08/04/exist-lucene-to-xml-syntax/:)
(:In Ron's script, single quotation marks can mark phrase and near searches. I do not think this is in accordance with Lucene search syntax (think of all the uses of the apostrophe, whereas double quotation marks are - as far as I can see - only used for inches on their own), so I have converted these into &quot;.:)
declare function local:parse-lucene($string) {
    (: replace all symbolic booleans with lexical counterparts :)
    (: if '&&', '||' or '!' are used :)
    if (matches($string, '[^\\](\|{2}|&amp;{2}|!) ')) 
    then
        let $rep := 
            replace(
            replace(
            replace(
                $string, 
            '&amp;{2} ', 'AND '), 
            '\|{2} ', 'OR '), 
            '! ', 'NOT ')
        return local:parse-lucene($rep)                
    else (: replace all booleans with '<AND/>|<OR/>|<NOT/>' :)
        if (matches($string, '[^<](AND|OR|NOT) ')) 
        then
            let $rep := replace($string, '(AND|OR|NOT) ', '<$1/>')
            return local:parse-lucene($rep)
    else (: replace all '+' modifiers with '<AND/>' :)
        if (matches($string, '(^|[^\w&quot;])\+[\w&quot;(]'))
        then
            let $rep := replace($string, '(^|[^\w&quot;])\+([\w&quot;(])', '$1<AND type=_+_/>$2')
            return local:parse-lucene($rep)
        else (: replace all '-' modifiers with '<NOT/>' :)
            if (matches($string, '(^|[^\w&quot;])-[\w&quot;(]'))
            then
                let $rep := replace($string, '(^|[^\w&quot;])-([\w&quot;(])', '$1<NOT type=_-_/>$2')
                return local:parse-lucene($rep)
            else (: replace round brackets with '<bool></bool>' :)
                (:Ron 2011-08-09: if (matches($string, '(^|\W|>)\(.*?\)(\^(\d+))?(<|\W|$)')):)
                if (matches($string, '(^|[\W-[\\]]|>)\(.*?[^\\]\)(\^(\d+))?(<|\W|$)'))                
                then
                    let $rep := 
                        (: add @boost attribute when string ends in ^\d :)
                        if (matches($string, '(^|\W|>)\(.*?\)(\^(\d+))(<|\W|$)')) 
                        then replace($string, '(^|\W|>)\((.*?)\)(\^(\d+))(<|\W|$)', '$1<bool boost=_$4_>$2</bool>$5')
                        else replace($string, '(^|\W|>)\((.*?)\)(<|\W|$)', '$1<bool>$2</bool>$3')
                    return local:parse-lucene($rep)
                else (: replace quoted phrases with '<near slop=""></bool>' :)
                    if (matches($string, '(^|\W|>)(&quot;).*?\2([~^]\d+)?(<|\W|$)')) 
                    then
                        let $rep := 
                            (: add @boost attribute when phrase ends in ^\d :)
                            if (matches($string, '(^|\W|>)(&quot;).*?\2([\^]\d+)?(<|\W|$)')) 
                            then replace($string, '(^|\W|>)(&quot;)(.*?)\2([~^](\d+))?(<|\W|$)', '$1<near boost=_$5_>$3</near>$6')
                            (: add @slop attribute in other cases :)
                            else replace($string, '(^|\W|>)(&quot;)(.*?)\2([~^](\d+))?(<|\W|$)', '$1<near slop=_$5_>$3</near>$6')
                        return local:parse-lucene($rep)
                    else (: wrap fuzzy search strings in '<fuzzy min-similarity=""></fuzzy>' :)
                        if (matches($string, '[\w-[<>]]+?~[\d.]*')) 
                        then
                            let $rep := replace($string, '([\w-[<>]]+?)~([\d.]*)', '<fuzzy min-similarity=_$2_>$1</fuzzy>')
                            return local:parse-lucene($rep)
                        else (: wrap resulting string in '<query></query>' :)
                            concat('<query>', replace(normalize-space($string), '_', '"'), '</query>')
};


(:@author: Ron Van den Branden, https://rvdb.wordpress.com/2010/08/04/exist-lucene-to-xml-syntax/:)
declare function local:lucene2xml($node) {
    typeswitch ($node)
        case element(query) return 
            element { node-name($node)} {
            element bool {
            $node/node()/local:lucene2xml(.)
        }
    }
    case element(AND) return ()
    case element(OR) return ()
    case element(NOT) return ()
    (:Ron 2011-08-09: case element(bool) return
        if ($node/parent::near) 
        then concat("(", $node, ")") 
        else element {node-name($node)} {
            $node/@*,
            $node/node()/local:lucene2xml(.)
        }:)
    case element() return
        let $name := 
            if (($node/self::phrase|$node/self::near)[not(@slop > 0)]) 
            then 'phrase' 
            else node-name($node)
        return 
        (: Ron: element { $name } {
          $node/@*,
          if (($node/following-sibling::*[1]|$node/preceding-sibling::*[1])[self::AND or self::OR or self::NOT]) then
            attribute occur { 
              if ($node/preceding-sibling::*[1][self::AND]) then 'must'
              else if ($node/preceding-sibling::*[1][self::NOT]) then 'not'
              else if ($node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) then 'should' 
              else 'should':)
            element { $name } {
                $node/@*,
                    if (($node/following-sibling::*[1] | $node/preceding-sibling::*[1])[self::AND or self::OR or self::NOT or self::bool])
                    then
                        attribute occur { 
                            if ($node/preceding-sibling::*[1][self::AND]) 
                            then 'must'
                            else 
                                if ($node/preceding-sibling::*[1][self::NOT]) 
                                then 'not'
                                else 
                                    if ($node[self::bool]and $node/following-sibling::*[1][self::AND])
                                    then 'must'
                                    else 
                                        if ($node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) 
                                        then 'should' (:must?:) 
                                        else 'should'
                        }
                    else ()
                    ,
                    $node/node()/local:lucene2xml(.)
        }
    case text() return
        if ($node/parent::*[self::query or self::bool]) 
        then
            for $tok at $p in tokenize($node, '\s+')[normalize-space()]
            (: here is the place for further differentiation between  term / wildcard / regex elements :)
            (: using regex-regex detection (?): matches($string, '((^|[^\\])[.?*+()\[\]\\^]|\$$)') :)
                let $el-name := 
                    (:Ron old: if (matches($node, '((^|[^\\])[?*]|\$$)')):)
                    if (matches($tok, '(^|[^\\])[$^|+\p{P}-[,]]'))
                    then 'wildcard'
                    else 
                        (:Ron old: if (matches($tok, '((^|[^\\])[.]|\$$)')):)
                        if (matches($tok, '(^|[^\\.])[?*+]|\[!'))
                        then 'regex'
                        else 'term'
                return 
                    element { $el-name } {
                        attribute occur {
                        (:if the term follows AND:)
                        if ($p = 1 and $node/preceding-sibling::*[1][self::AND]) 
                        then 'must'
                        else 
                            (:if the term follows NOT:)
                            if ($p = 1 and $node/preceding-sibling::*[1][self::NOT])
                            then 'not'
                            (:Ron: else if ($p = 1 and $node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) then 'should' (\:'must':\):)
                            else (:if the term is preceded by AND:)
                                if ($p = 1 and $node/following-sibling::*[1][self::AND])
                                then 'must'
                                    (:Ron begins: if ($p = 1 and $node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) then 'should':Ron ends:)
                                    (:if the term follows OR and is preceded by OR or NOT, or if it is standing on its own:)
                                else 'should'
                    }
                    ,
                    if (matches($tok, '(.*?)(\^(\d+))(\W|$)')) 
                    then
                        attribute boost {
                            replace($tok, '(.*?)(\^(\d+))(\W|$)', '$3')
                        }
                    else ()
        ,
        normalize-space(replace($tok, '(.*?)(\^(\d+))(\W|$)', '$1'))
        }
        else normalize-space($node)
    default return
        $node
};
