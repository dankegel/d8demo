= Drupal 8 demo for Ubuntu 15.10

Here's how to install Drupal 8 using Composer and Drush.

First, read the script d8demo.sh before running it.  
It's executable documentation, meant more as a learning aid than a tool.

To create a container named 'd8demo' for drupal 8, and open a browser to its future home page:
```
$ ./d8demo.sh create
```

To install drupal 8's dependencies inside the container:
```
$ ssh d8demo ./d8demo.sh deps
```

To install drupal 8 inside the container:
```
$ ssh d8demo ./d8demo.sh install
```

After running that, reload http://d8demo/ in your browser, and you should see the home page for your drupal 8 install.
