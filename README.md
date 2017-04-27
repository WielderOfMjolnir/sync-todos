<div id="table-of-contents">
<h2>Table of Contents</h2>
<div id="text-table-of-contents">
<ul>
<li><a href="#org9edfe37">1. Description</a></li>
<li><a href="#org697e97d">2. Requirements</a></li>
<li><a href="#org695b1fd">3. How-to</a></li>
</ul>
</div>
</div>


<a id="org9edfe37"></a>

# Description

A "thrown-together-in-a-day" package for syncing my Org TODOs
with the corresponding projects on Asana (currently) and Gitlab (eventually).


<a id="org697e97d"></a>

# Requirements

-   org
-   [emacs-asana](https://github.com/lmartel/emacs-asana)


<a id="org695b1fd"></a>

# How-to

First you need to expose your Asana Token as an environment variable
named `ASANA_TOKEN`.

Then it assumes you have the following structure:

-   `ASANA_PROJECT_ID` on a org-headline means that the entire subtree of
    this element will be related to the corresponding project, let's call
    it a `project-headline`.
-   `ASANA_TASK_ID` on a org-headline with `TODO` under a 
    `project-headline` will be treated as a Asana task.

The following conditions define how synchronization happens:

-   Local tasks will only take cause a remote update if either of the following
    is true:
    -   Task does not exist in Asana yet, i.e. no `ASANA_TASK_ID` property
        is attached to the todo in Org. In this case, the local todo will
        be assigned the ID of the newly created task.
    -   Task which is in both Asana and Org, with a `ASANA_TASK_ID` property,
        is `DONE` while the Asana task is not completed.

-   Remote tasks will cause local updates if either of the following is true:
    -   Task does not exist locally
    -   Task is completed on remote but not on local

