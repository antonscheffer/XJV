# XJV
A small function to get data from a JSON varchar2 using JSON-path selectors.<br/>
Might be useful on pre 12.2 databases.<br/>
I use it to parse configuration files or input parameters.<br/>
This functions assumes that you know the structure of the JSON string. You need to know where to find the value you are looking for.<br/>
And it only returns one value, no sets. So a wildcard like [*] to get all the values from a array won't work.
~~~
declare
  ... <function xjv>
begin
  dbms_output.put_line( xjv( '{"a":"A","c":{},"d":{"e":"\"\\\" 15\u00f8C \u20ac 20"}}', 'd.e' )  );
  dbms_output.put_line( xjv( '{"a":{"b":[{},{},{"c":[0,1,2,3,4]}]}}', 'a.b[2].c[3]' )  );
end;

"\" 15øC € 20
3
~~~
# json_minifier
A small function which minifies a JSON clob. It only removed white space.
~~~
declare
  l_x clob;
  l_json clob;
  ... <function json_minifier>
begin
  l_json := q'~{ "\"\\\" 15\u00f8C \u20ac 20" : 12   ,   'x' : [  true,null  , false,{  }  , [ ]   ,  "x123"  , "test" ] }~';
  l_x := json_minifier( l_json );
  dbms_output.put_line( 'from ' || dbms_lob.getlength( l_json ) || ' to ' || dbms_lob.getlength( l_x ) );
  dbms_output.put_line( l_x );
end;

from 107 to 75
{"\"\\\" 15\u00f8C \u20ac 20":12,'x':[true,null,false,{},[],"x123","test"]}
~~~
