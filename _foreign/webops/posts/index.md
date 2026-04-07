---
title: All Posts
layout: base.njk
---

# All Posts

## Latest

{% raw %}
{% for post in collections.post | reverse %}
- [{{ post.data.title }}]({{ post.url }})
{% endfor %}
{% endraw %}
