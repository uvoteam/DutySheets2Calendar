# DutyShifts

This is a simple script, that takes Google spreadsheet document, extracts
schedule information from it, and sets up events in Google calendar accordingly.

It is tailored for my needs, but can be used as an example for your own
automation.

So, at work duty admins have a google spreadsheet, where they have a sheet per
month, and their shifts are recorded like this:

```
date   --1-- --2-- --3-- --4-- ...
admin1  -  - 12  -  - 12  -  - ...
admin2  - 12  -  - 12  -  - 12 ...
admin3 12  -  - 12  -  - 12  - ...
```

Shifts occasionally fall out of the pattern, thus I decided to make them
available in my pone's calendar. Not that google calendar is that useful for
alarms - it does not allow to set notification sounds separately for timed
events and wholeday events (you don't want an alarm at 8 o'clock in the Sunday
three days before your dog's birthday, do you?), but it is much more convenient 
to have at least some form of notification.

## Install

Unfortunately, google gems are not packaged by debian, so, you'll need to
install them manually. The easiest way (for me) is to do unprivileged install
with bundler. This ties your script to specific directory (and bundler), but
does not require messing with the system manually.

So, the recipe is as follows (Debian):

```shell
# aptitude install bundler
$ git clone $projecturl duty-shifts
$ cd duty-shifts
$ bundler install --path=vendor/bundle
$ cp config.example.yaml config.yaml
```

## Setup

So, now you have default config file, that you will need to fill in with correct
values. Theres not much of them, but some do require some work to obtain. Thus,
let's begin.

First of all - you need your spreadsheet ID. Just open it in browser and copy
long hash from url - it's the part between `/spreadsheet/d/` and `/edit`.

If your username on the machine, where you'll run script, differs from the one,
specified in the spreadsheet - fill that as well.

When creating events in the calendar, you have an option to specify time (in
minutes) to create notifications before event (your shift) will kick in. They
are optional, and you can specify any amount of them.

Script keeps his events in a separate 'calendar', by default it names it
'DutyShifts', but you can override this value in the config file. Do not modify
this calendar, since script will delete and recreate it anew, when clearing old
events.

Now for the tricky part. You need to give script access to your spreadsheet and
to your calendar.

First - of course, your account needs access to spreadsheet, so, it must be
shared with the account, you will be importing calendar to. Read-only is
sufficient.

Second - you need to go to google api console
(https://console.developers.google.com) and create a 'project'. You can name it
any way you wish.

After creation you'll need to go to Library and add an 'API' to your project.
We will need 'Sheets API' and 'Calendar API'. Just tap them, and then press
'enable' button on the next page.

Google will notify you, that you will also need 'credentials' to be able to use
these apis. We'll use oauth authorization, so, first you go into 'Credentials'
section on the left, then 'OAuth consent screen' tab, and there write something
in the 'Product name' field.  After that you need to go to the 'Credentials'
tab, and create new 'OAuth client ID'. You can select an 'other' type and write
something in the 'Name' field. Doing so will present you with window, where you
can copy values for fields `user_id` and `secret` in our configuration file.

## Run

Congratulations! This should be it. Now, if you type (in the project dir)

```shell
bundler exec ./main.rb
```

script will examine your sheet and create events in your calendar.

First time use of new credentials will require a confirmation from you. Script
will print an url, that you will need to open in your browser, and expects you
to copypaste the code, that google will provide. This creates an 'auth token',
that script will use from now on. This auth token will be stored in the file
'store.yaml' (this path can be overridden in the config file as well).

  -- Mykhailo Danylenko <isbear@isbear.org.ua>
