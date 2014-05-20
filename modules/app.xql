xquery version "3.0";

module namespace app="http://exist-db.org/apps/wolfslaw/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://exist-db.org/apps/wolfslaw/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

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
                    <p>No search term specified.</p>
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
                switch($target-field)
                    case "title" return
                        $context//tei:div/tei:head[@type eq 'subtitle'][ft:query(., $query)]
                    default (:text:) return
                        $context//tei:div[ft:query(., $query)][not(tei:div)]
        return
                let $query-strings := $query//term/text()
                let $query-strings := if ($query-strings) then $query-strings else tokenize($query//phrase/text(), ' ')
                let $query-result :=
                    <result>{
                        for $query-string in $query-strings
                        return
                            if (app:get-terms($query-string))
                            then <present>{$query-string}</present>
                            else <absent>{$query-string}</absent>
                    }</result>
                return
                    if ($query-result//absent)
                    then app:suggest($query-result)
            else        
                let $sorted :=
                            for $result in $results
                            order by ft:score($result) descending
                            return
                                $result
                let $cached := session:set-attribute("wolfslaw.cached-data", $sorted)
                        return
                            map {
                                "results" := $sorted
                    }
    };


(:~
    Helper function: create a lucene query from the user input
:)
(:TODO: implement <wildcard> and <regex>.:)
declare function app:create-query() {
    let $queryStr := request:get-parameter("query", ())
    let $queryStr := normalize-space($queryStr)
    let $mode := request:get-parameter("mode", "any")
    return
        <query>
        {
            if ($mode eq 'any') then
                for $term in tokenize($queryStr, '\s')
                return
                    <term occur="should">{$term}</term>
            else if ($mode eq 'all') then
                <bool>
                {
                    for $term in tokenize($queryStr, '\s')
                    return
                        <term occur="must">{$term}</term>
                }
                </bool>
            else if ($mode eq 'phrase') then
                <phrase>{$queryStr}</phrase>
            else
                <near slop="5" ordered="no">
                {
                    for $term in tokenize($queryStr, '\s')
                    return
                        <term>{$term}</term>
                }
                </near>
        }
        </query>
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
    let $class := if ($hit-count) then 'col-md-3 alert alert-success' else 'col-md-3 alert alert-danger' 
    return
        <div class="{$class}">Found <b class="btn btn-default" data-template="app:result-count">{$hit-count}</b> hits.</div>
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

declare function app:get-terms($prefix as xs:string) {
    util:index-keys(collection($config:app-root)//tei:div[not(tei:div)], $prefix, 
        function($term as xs:string, $count as xs:int+) {
            <term name="{$term}" freq="{$count[1]}"/>
        }, 
        -1, "lucene-index")
};

declare function app:suggest($query-result as element()) {
let $present := $query-result//present
let $absent := $query-result//absent
    return 
        if ($present)    
        then <div class="query-result">One or more of your search terms did not bring any hits. <span class="query-term">{string-join($present, ', ')}</span> brought hits, but <span class="query-term">{string-join($absent, ', ')}</span> did not. Suggestions for words you might use instead are listed below.</div>
        else <div class="query-result">One or more of your search terms did not bring any hits. <span class="query-term">{string-join($absent, ', ')}</span> did not. Suggestions for words you might use instead are listed below.</div>
        ,
        for $absent in $query-result//absent
        return    
            <ul class="list-group">
            {
                let $words := app:get-terms(substring($absent, 1, 2))
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
            </ul>
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
