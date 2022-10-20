---
layout: tag
title: "Tag: linux"
permalink: /t/linux
---

<ul class="post-list, mainpage_element">
  {%- for post in site.tags["linux"] -%}
    <li>
      {%- assign date_format = site.minima.date_format | default: "%b %-d, %Y" -%}
      <!--<span class="post-meta">-->
        {{ post.data | date: date_format }}
      <!--</span>-->
      <h3>
        <a class="post-link" href="{{ post.url | relative_url }}">
          <img src="{{- post.image | relative_url -}}" alt="" class="blog-roll-image">
          {{ post.title | escape }}
        </a><br>
	<time datetime="{{ post.date | date_to_xmlschema }}" style="font-size: 12px;">{{ post.date | date_to_string }}</time>
      </h3>
    </li>
  {%- endfor -%}
</ul>
