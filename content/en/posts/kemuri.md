---
date: "2026-07-29T00:00:00+02:00"
draft: false
tags:
  - linux
  - network
  - observability
title: "Creating a modern SmokePing inspired tool in Rust"
description: ""
images:
  - ""
---

[SmokePing](http://www.smokeping.org/) is a good old reliable system for network monitoring created by Tobias Oetiker and Niko Tyni, written in Perl.

It is an amazing tool and satisfies a specific niche, but it is [hard to install](https://oss.oetiker.ch/smokeping/doc/smokeping_install.en.html).

I've been talking to various colleagues .. half jokingly a colleague and I talked about how cool it would be if we made something similar from scratch in Rust.

The other day when I looked at my Github profile I realized that I wasn't satisfied with my pinned repositories.
That's when I remembered this potential project and immediately opened ChatGPT and started voice prompting.

ChatGPT Sol 5.6 Pro -> Specification .md file -> GLM 5.2 on [Intility Inference]() -> Initial scaffolding and MVP -> Codex Sol 5.6 medium -> Final polish and v1 release

I chose the name "Kemuri" simply because it means "smoke" in Japanese.

## Realities

Does this actually work in production environments? I don't know.

Would I even maintain this? Maybe.
