xquery version "3.0";

import module namespace config="http://exist-db.org/apps/wolfslaw/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

let $codesAsEvents :=
    <data>{
        for $code in collection($config:data-root)//tei:TEI return
            <event  id="{$code/@xml:id}"
                    title="{$code/tei:teiHeader//tei:title[@type]/text()}"
                    link="../../toc.html?id={$code/@xml:id}"
                    start="{$code/tei:teiHeader//tei:publicationStmt/tei:date}">
                {$code/tei:teiHeader//tei:title[not(exists(@type))]/text()}
            </event>
    }</data>
return
    $codesAsEvents