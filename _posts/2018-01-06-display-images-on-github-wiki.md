---
layout: post
title:  "Display images on GitHub wiki"
date:   2018-01-06 19:04:44 +0200
tags: [programming, github, github-wiki]
---

<!-- markdownlint-disable MD022 -->
# Context
After giving a [Rancher](https://rancher.com/rancher/) workshop during the 5th edition of the Java Tech Group Day, an [iQuest](http://www.iquestgroup.com/en/) internal event, which took place on September 7th 2017, I thought about open-source it on GitHub as a series of wiki pages to let people outside this company benefit from it too.  
After getting the OK from the Java Practice leadership to publish it on [GitHub](https://github.com/satrapu/rancher-workshop), I started converting the workshop written as a series of Confluence pages to one of the formats supported by [GitHub wiki](https://help.github.com/articles/about-github-wikis/): [Markdown](https://daringfireball.net/projects/markdown/).  
Below you may find how I ended-up displaying the workshop images on GitHub wiki pages.

# Approach #1: GitHub repo image relative URL
Since the workshop was built as a series of step-by-step tutorials, it contained lots of high-resolution images; see one [here](https://github.com/satrapu/rancher-workshop/blob/master/images/scenarios/basic/01/image2017-8-19_22-23-22.png). My first approach was to store them in the GitHub repository where my wiki pages were located too. A wiki page would link such an image, but the end result was a resized image which required the user to resort to browser zoom-in to clearly see the image and then zoom out to read the text - a pretty awful user-experience!  
Anyway, the image is displayed in a wiki page via this Markdown fragment:

```markdown
![](https://github.com/satrapu/rancher-workshop/blob/master/images/scenarios/basic/01/image2017-8-19_22-23-22.png)
```

The page revision using the above URL can be found [here](https://github.com/satrapu/rancher-workshop/wiki/VirtualBox/105870481d0afe58360e57f2fa0f7f636cc94955) (scroll down to the "VirtualBox VM Installation Steps" section).  

# Approach #2: GitHub "raw" image absolute URL
As you can imagine, I wasn't very happy with the first approach, as it brought a poor user-experience - a thing I could not tolerate for *my* workshop!  
Accidentally, I stumbled upon other GitHub wikis showing high-res images and when I took a closer look at one of their images - bingo! The image URL was using a different domain than a normal GitHub repo would: __raw.githubusercontent.com__ instead of __github.com__.
Additionally, to further improve the user-experience, I wanted to enlarge the image to its original size when clicked and thus I had to resort to plain HTML markup: have an *a* tag include an *img* one.  
After applying these changes, the aforementioned image fragment became:

```html
<a href="https://raw.githubusercontent.com/satrapu/rancher-workshop/master/images/scenarios/basic/01/image2017-8-19_22-23-22.png" target="_blank">
  <img src="https://github.com/satrapu/rancher-workshop/blob/master/images/scenarios/basic/01/image2017-8-19_22-23-22.png" />
</a>
```

Please note that the *img* tag will render a down-sized image, while clicking the link will render the original high-res image.  
The page using the above URL can be found [here](https://github.com/satrapu/rancher-workshop/wiki/VirtualBox) (scroll down to the "VirtualBox VM Installation Steps" section).  
The only thing I'm still not able to figure it out is how to open the original image in a different browser tab. I've tried setting "target=_blank" attribute to the *a* tag, but without any result. Anyway, the end result is a better user-experience, so my goal has been reached.

# Conclusion
GitHub wiki is a good way of sharing information and it has good support for content presentation, high-res images included.
