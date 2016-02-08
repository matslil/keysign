GPG key signing tools
=====================

After attending a key signing party, I wanted to sign around 150 GPG keys,
preferably not manually. I saw Debian caff tool, but letting a script that
I cannot easily penetrate what it will do with my keys is something I just
couldn't do.

So I created a serie of bash scripts. Using bash since I know it well, but
also since it is closer to how you would do it from the command prompt and
therefore easier to understand what it does.

The three tools are:

 -  dl-key.sh
 -  sign.sh
 -  send-email.sh

The reason for having three tools is that the second tool, sign.sh, might
need to be run from an air-gap computer, while the other two tools require
Internet connection.

For more information about each script, please read the scripts. They are
well commented. Also note that the script "sign.sh" needs to be modified
with your configurations, and will therefore not work out of the box.
Do this before you run dl-key.sh, since dl-key.sh will copy sign.sh to
its output directory.

If you cannot find send-email.sh script then it is because I haven't written
it yet.

