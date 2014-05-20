xquery version "3.0";

module namespace app="http://exist-db.org/apps/wolfslaw/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://exist-db.org/apps/wolfslaw/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare
    %templates:wrap
    %templates:default("type", "text")
function app:search($node as node(), $model as map(*), $qu as xs:string?, $type as xs:string) {
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
        let $results := 
            switch($type)
                case "title" return
                    collection($config:app-root)//tei:div[ft:query(tei:head, $qu)]
                default return
                    collection($config:app-root)//tei:div[ft:query(., $qu)][not(tei:div)]
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
        return
            <tr>
                <td>{$result/ancestor::tei:TEI//tei:titleStmt/tei:title[@type="short"]/text()}</td>
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

declare function app:process($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
            case element(exist:match) return
                <mark>{$node/text()}</mark>
            case element(tei:body) return
                app:process($node/*)
            case element(tei:div) return
                <div>{app:process($node/node())}</div>
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