xquery version "3.0";

module namespace app="http://exist-db.org/apps/wolfslaw/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://exist-db.org/apps/wolfslaw/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare
    %templates:wrap
    %templates:default("type", "text")
function app:search($node as node(), $model as map(*), $qu as xs:string?, $type as xs:string, $law as xs:string?) {
    if (empty($qu) or $qu = "") then
        let $cached := session:get-attribute("wolfslaw.cached-data")
        return
            if (empty($cached)) then
                <p>No search term specified.</p>
            else
                map {
                    "results" := $cached
                }
    else
        let $context := 
            if (empty($law) or $law = "") then
                collection($config:app-root)
            else
                collection($config:app-root)/id($law)
(:                collection($config:app-root)/tei:TEI[@xml:id = $law]:)
        let $results := 
            switch($type)
                case "title" return
                    $context//tei:div[ft:query(tei:head, $qu)]
                default return
                    $context//tei:div[ft:query(., $qu)][not(tei:div)]
        return
            if (empty($results)) then
                app:suggest($qu)
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
    <table class="table table-striped">
    {
        for $result in subsequence($model("results"), $start, 20)
        let $shortTitle := $result/ancestor::tei:TEI//tei:titleStmt/tei:title[@type="short"]/text()
        return
            <tr>
                <td>
                    <a class="btn btn-default" href="view.html?short={$shortTitle}#{generate-id($result)}">{$shortTitle}</a>
                </td>
                <td>{ app:process(util:expand($result)) }</td>
            </tr>
    }
    </table>
};

declare
    %templates:wrap
function app:result-count($node as node(), $model as map(*)) {
    count($model("results"))
};

declare 
    %templates:wrap
function app:table-of-contents($node as node(), $model as map(*)) {
    for $law in collection($config:data-root)//tei:TEI
    let $title := $law//tei:titleStmt/tei:title[not(@type)]/text()
    let $short := $law//tei:titleStmt/tei:title[@type="short"]/text()
    return
    <tr>
        <td>{$short}</td>
        <td><a href="view.html?short={$short}">{$title}</a></td>
    </tr>
};

declare
    %templates:wrap
function app:load($node as node(), $model as map(*), $short as xs:string) {
    let $law := collection($config:data-root)/tei:TEI[
        .//tei:fileDesc/tei:titleStmt/tei:title[@type = "short"][. = $short]
    ]
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
    util:index-keys(collection("/db/apps/wolfslaw")//tei:div[not(tei:div)], $prefix, 
        function($term as xs:string, $count as xs:int+) {
            <term name="{$term}" freq="{$count[1]}"/>
        }, 
        -1, "lucene-index")
};

declare function app:suggest($term as xs:string) {
    <ul class="list-group">
    {
        let $words := app:get-terms(substring($term, 1, 2))
        let $before := $words[@name < $term]
        let $after := $words[@name > $term]
        let $merged := (
            subsequence($before, count($before) - 10),
            subsequence($after, 1, 10)
        )
        for $term in $merged
        return
            <li class="list-group-item">
            <a href="?qu={$term/@name}">{$term/@name/string()}</a> <span class="badge">{$term/@freq/string()}</span>
            </li>
    }
    </ul>
};

declare function app:process($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
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