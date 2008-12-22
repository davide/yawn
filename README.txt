Yawn - "Yaws Nest". 
An easy way to deploy various webapps on a yaws server.

RUNNING IT:

- Including yawn in your projects

	Setting up yawn is similar to setting up yaws_vdir.
	  - Make sure to have yawn.beam in your ebin path;
	  - Add the line:
		arg_rewrite_mod = yawn
	    to the server configuration section of your yaws config;
	  - Set up a opaque yawn variable for each appmod you
	    want yawn to handle.
	    The yaws.conf file provided with yaws (or the details at
	    the end of this file) are self explanatory.
	  - Enjoy!

- Using the provided yaws.conf

	The given yaws configuration file has been created to load two
	webapps: noe (http://github.com/davide/noe/tree/packaged)
	and twoorl (http://github.com/davide/twoorl/tree/packaged).
	These apps only run using a version of erlyweb that was 
	extended to add support for erlang's packages (you can download
	it here: http://github.com/davide/erlyweb/tree/erlyweb-packaged).
	
	  - Install erlyweb-packaged;
	  - Install noe;
	    - edit the src/app.hrl file and fill in the correct settings
	    - open a console, go to noe's directory and type:
		make
	  - Install twoorl;
	    - edit the src/app.hrl file and fill in the correct settings
	    - open a console, go to twoorl's directory and type:
		make
	  - Fix the paths to noe and twoorl in the yaws.conf file;
	  - Open a console, go to yawn's directory and type:
		make run

	    This should:
	      - load yaws using the ./yaws.conf file
	      - run noe.boot:start()
	      - run twoorl.boot:start()

	If all goes well you should now be able to access noe via:
	  - http://localhost/noe
	and twoorl via:
	  - http://localhost/twoorl
	
	Notice:
	  - At the time of this writting erlyweb-packaged still had some issues
	    sandboxing apps (an issue regarding models compilation).


RATIONALE and MINDLESS BLA BLA BLA:
When I started using Yaws one of the things I first tried to do was to
deploy two erlyweb webapps on the same server. The problem was that
erlyweb read an unique appname opaque variable, so that stopped me
from simply setting up two appmods.
The only solution seemed to be using Yapps and registering the
two webapps.
The docs state: "In order to make a "yapp" we need to know how to
make an ordinary Erlang application".
One word: overkill! This is just too much to ask for someone trying to
get their feets wet with Yaws/Erlang.
A person should be able to play around for a bit before *having to* plung
into OTP.
I disliked using Yapps so much (not that it's not good, I was just that
much of a noob :P) that I ended up trying to hack erlyweb to inject
sanboxing abilities (using yaws_vdir as an helper).

After some iterations I realized part of what what I'd done could be
refactored. And so Yawn was born! :)
Yaws' main advantages are that it enables 1) docroot switching; and
2) opaque variables redefinition, on a per-appmod basis - like Yapp does -
but with a simpler to install and use (for noobs at least) approach.

Nothing better than a quick example to show how it works!
Starting of with this server configuration:
<server localhost>
        port = 80
        listen = 0.0.0.0
        docroot = www
	appmods = <"/noe", erlyweb>
        <opaque>
		yawn = "/noe, appname = noe, docroot = c:/erlyapps/noe/www, key1 = value1, key2 = value2"
        </opaque>
	arg_rewrite_mod = yawn
</server>

If yaws gets a request for a page under http://localhost/noe/ it will rewrite
the request into:
<server localhost>
        port = 80
        listen = 0.0.0.0
        docroot = c:/erlyapps/noe/www
	appmods = <"/noe", erlyweb>
        <opaque>
		yawn = "/noe, docroot = c:/erlyapps/noe/www, key1 = value1, key2 = value2"
		key1 = "value1"
		key2 = "value2"
        </opaque>
	arg_rewrite_mod = yawn
</server>
Additionally, it will call yaws_vdir before returning #arg to yaws.

The yawn opaque variable values should start with the appmod
URI followed by a comma and a list of comma separated "key = value"
pairs (of which only the docroot key is mandatory). This can change in the future!

This module only exists because I was able to study yapp,
yaws_vdir and yaws' source code. A special thanks to the authors! ;)

Enjoy!
Davide :)