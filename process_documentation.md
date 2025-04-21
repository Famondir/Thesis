# Process documentation

## Kubenetes Tutorial

### First app

At [first app](https://docs.cluster.ris.bht-berlin.de/user/firstapp/) the command 
```
kubectl exec -it firstpod bash
```
is given. But for me it only worked after i added a `--` in front of the `bash`:
```
kubectl exec -it firstpod -- bash
```

The shell is exited with the command `exit`.

In [Headlamp](https://dashboard.cluster.ris.bht-berlin.de/c/main/) I have no permissions.

## Bookdown gitbook

The command
```
site: "bookdown::bookdown_site"
```
in the yaml head helps to bundle all `.Rmd` documents. But it might have prevented the `libs` folder getting filled with necessary CSS and JavaScript files.

To build the whole book and not only the `index.Rmd` properly use the command 
```
bookdown::render_book('index.Rmd', 'bookdown::gitbook')
```
or the **Build** menu entry in RStudio. Otherwise one gets empty `.html` files (or they don't get updated).

## PDF to Markdown

There are some new nice Python packages for this task and Azure also performs pretty well. The old packages without LLM support are really outperformed especially with respect to tables.

There have been some dependency issues after installing `torch` just with the Python packages like `maker-pdf` and `docling`. Reinstalling it manually with `pip` and checking for the CPU version for the local virtual machine solved the issues. Especially for `sympy` some packages need version 1.13.1 and not the newer version 1.13.3.

## GLIBCXX not found fpr xgrammar

[Solution](https://github.com/deepspeedai/DeepSpeed/issues/2886)