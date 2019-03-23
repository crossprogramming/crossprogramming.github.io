---
layout: page
permalink: /tags/
title: Tags
---
<!-- markdownlint-disable MD033 -->
<div id="archives">

{% assign sorted_site_tags = site.tags | sort %}

{% for tag in sorted_site_tags %}
  <div class="archive-group">

    {% capture tag_name %}{{ tag | first }}{% endcapture %}

    <div id="#{{ tag_name | slugize }}"></div>

    <h2 class="-head">{{ tag_name }}</h2>

    <a name="{{ tag_name | slugize }}"></a>

    {% for post in site.tags[tag_name] %}
      <article class="archive-item">
        <h8><a href="{{ site.baseurl }}{{ post.url }}">{{post.title}}</a></h8>
      </article>
    {% endfor %}

    <p/>
  </div>
{% endfor %}
</div>