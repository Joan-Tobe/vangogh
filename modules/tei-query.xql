(:
 :
 :  Copyright (C) 2017 Wolfgang Meier
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

module namespace teis="http://www.tei-c.org/tei-simple/query/tei";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation/tei" at "navigation-tei.xql";

declare variable $teis:QUERY_OPTIONS := map {
    "leading-wildcard": "yes",
    "filter-rewrite": "yes"
};

declare function teis:query-default($fields as xs:string+, $query as xs:string, $target-texts as xs:string*) {
    if(string($query)) then
        for $field in $fields
        return
            switch ($field)
                case "head" return
                    if ($target-texts) then
                        for $text in $target-texts
                        return
                            $config:data-root ! doc(. || "/" || $text)//tei:head[ft:query(., $query, teis:options())]
                    else
                        collection($config:data-root)//tei:head[ft:query(., $query, teis:options())]
                default return
                    if ($target-texts) then
                        for $text in $target-texts
                        return
                            $config:data-root ! doc(. || "/" || $text)//tei:div[ft:query(., $query, teis:options())] |
                            $config:data-root ! doc(. || "/" || $text)//tei:body[ft:query(., $query, teis:options())]
                    else
                        collection($config:data-root)//tei:div[ft:query(., $query, teis:options())] |
                        collection($config:data-root)//tei:body[ft:query(., $query, teis:options())]
    else ()
};

declare function teis:options() {
    map:merge((
        $teis:QUERY_OPTIONS,
        map {
            "facets":
                map:merge((
                    for $param in request:get-parameter-names()[starts-with(., 'facet-')]
                    let $dimension := substring-after($param, 'facet-')
                    return
                        map {
                            $dimension: request:get-parameter($param, ())
                        }
                ))
        }
    ))
};


declare function teis:query-metadata($field as xs:string, $query as xs:string, $sort as xs:string) {
    let $options := map:merge((teis:options(), map { "fields": $sort }))
    for $rootCol in $config:data-root
    for $doc in collection($rootCol)//tei:body[ft:query(., $field || ":" || $query, $options)]
    return
        $doc/ancestor::tei:TEI
};

declare function teis:autocomplete($doc as xs:string?, $fields as xs:string+, $q as xs:string) {
    for $field in $fields
    return
        switch ($field)
            case "from" return
                collection($config:data-root)/ft:index-keys-for-field("from", $q,
                    function($key, $count) {
                        $key
                    }, 30)
            case "to" return
                collection($config:data-root)/ft:index-keys-for-field("to", $q,
                    function($key, $count) {
                        $key
                    }, 30)
            default return
                collection($config:data-root)/ft:index-keys-for-field("title", $q,
                    function($key, $count) {
                        $key
                    }, 30)
};


declare function teis:get-parent-section($node as node()) {
    ($node/self::tei:body, $node/ancestor-or-self::tei:div[1], $node)[1]
};

declare function teis:get-breadcrumbs($config as map(*), $hit as element(), $parent-id as xs:string) {
    let $work := root($hit)/*
    let $work-title := nav:get-document-title($config, $work)/string()
    return
        <div class="breadcrumbs">
            <a class="breadcrumb" href="{$parent-id}">{$work-title}</a>
            {
                for $parentDiv in $hit/ancestor-or-self::tei:div[tei:head]
                let $id := util:node-id(
                    if ($config?view = "page") then ($parentDiv/preceding::tei:pb[1], $parentDiv)[1] else $parentDiv
                )
                return
                    <a class="breadcrumb" href="{$parent-id || "?action=search&amp;root=" || $id || "&amp;view=" || $config?view || "&amp;odd=" || $config?odd}">
                    {$parentDiv/tei:head/string()}
                    </a>
            }
        </div>
};

(:~
 : Expand the given element and highlight query matches by re-running the query
 : on it.
 :)
declare function teis:expand($data as element()) {
    let $query := session:get-attribute($config:session-prefix || ".query")
    let $field := session:get-attribute($config:session-prefix || ".field")
    let $div :=
        if ($data instance of element(tei:pb)) then
            let $nextPage := $data/following::tei:pb[1]
            return
                if ($nextPage) then
                    if ($field = "text") then
                        (
                            ($data/ancestor::tei:div intersect $nextPage/ancestor::tei:div)[last()],
                            $data/ancestor::tei:body
                        )[1]
                    else
                        $data/ancestor::tei:body
                else
                    ($data/ancestor::tei:div, $data/ancestor::tei:body)[1]
        else
            $data
    let $expanded :=
        util:expand(teis:query-default-view($div, $query, $field), "add-exist-id=all")
    return
        if ($data instance of element(tei:pb)) then
            $expanded//tei:pb[@exist:id = util:node-id($data)]
        else
            $expanded
};


declare %private function teis:query-default-view($context as element()*, $query as xs:string, $fields as xs:string+) {
    for $field in $fields
    return
        switch ($field)
            case "head" return
                $context[./descendant-or-self::tei:head[ft:query(., $query, $teis:QUERY_OPTIONS)]]
            default return
                $context[./descendant-or-self::tei:div[ft:query(., $query, $teis:QUERY_OPTIONS)]] |
                $context[./descendant-or-self::tei:body[ft:query(., $query, $teis:QUERY_OPTIONS)]]
};

declare function teis:get-current($config as map(*), $div as element()?) {
    if (empty($div)) then
        ()
    else
        if ($div instance of element(tei:teiHeader)) then
            $div
        else
            if (
                empty($div/preceding-sibling::tei:div)  (: first div in section :)
                and count($div/preceding-sibling::*) < 5 (: less than 5 elements before div :)
                and $div/.. instance of element(tei:div) (: parent is a div :)
                and count($div/preceding::tei:div) > 1
            ) then
                nav:get-previous-div($config, $div)
            else
                $div
};
