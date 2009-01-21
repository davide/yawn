all: code

code: clean
	erl -s make all load -s init stop

run:
	erl -noshell -eval 'filelib:ensure_dir("./log/").' -pa ebin -s erlang halt
	erl -yaws debug -run yaws -yaws id yawn -conf priv/yaws.conf

clean:
	rm -fv ebin/*.beam yawn.rel yawn.script yawn.boot erl_crash.dump *.log *.access

cleandb:
	rm -rfv *.mnesia Mnesia*

cleandocs:
	rm -fv doc/*.html
	rm -fv doc/edoc-info
	rm -fv doc/*.css
	rm -fv doc/*.png
