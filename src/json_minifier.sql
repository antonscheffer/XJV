declare
  l_x clob;
   l_json clob;
  function json_minifier( p_json clob )
  return clob character set p_json%charset
  is
    l_rv clob character set p_json%charset;
    --
    c_double_quote  constant varchar2(1) character set p_json%charset := n'"';
    c_single_quote  constant varchar2(1) character set p_json%charset := n'''';
    c_back_slash    constant varchar2(1) character set p_json%charset := n'\';
    c_space         constant varchar2(1) character set p_json%charset := n' ';
    c_colon         constant varchar2(1) character set p_json%charset := n':';
    c_comma         constant varchar2(1) character set p_json%charset := n',';
    c_end_brace     constant varchar2(1) character set p_json%charset := n'}';
    c_start_brace   constant varchar2(1) character set p_json%charset := n'{';
    c_end_bracket   constant varchar2(1) character set p_json%charset := n']';
    c_start_bracket constant varchar2(1) character set p_json%charset := n'[';
    c_ht            constant varchar2(1) character set p_json%charset := unistr( '\0009' );
    c_lf            constant varchar2(1) character set p_json%charset := unistr( '\000A' );
    c_cr            constant varchar2(1) character set p_json%charset := unistr( '\000D' );
    c_ws            constant varchar2(4) character set p_json%charset := c_space || c_ht || c_cr || c_lf;
    --
    g_idx number;
    g_end number;
    --
    procedure skip_whitespace
    is
    begin
      while dbms_lob.substr( p_json, 1, g_idx ) in ( c_space, c_lf, c_cr, c_ht )
      loop
        g_idx:= g_idx+ 1;
      end loop;
      if g_idx > g_end
      then
        raise_application_error( -20001, 'Unexpected end of JSON' );
      end if;
    end;
    --  
    procedure copy_value;
    procedure copy_array;
    --
    procedure append( p_start integer, p_len integer )
    is
    begin
      if p_len < 32767
      then
        dbms_lob.writeappend( l_rv, p_len, dbms_lob.substr( p_json, p_len, p_start ) );
      else
        dbms_lob.copy( l_rv, p_json, p_len, dbms_lob.getlength( l_rv ) + 1, p_start );
      end if;
    end;
    --
    procedure copy_object
    is
    begin
      if dbms_lob.substr( p_json, 1, g_idx ) = c_start_brace
      then
        append( g_idx, 1 );
        g_idx := g_idx + 1;
        loop
          skip_whitespace;
          exit when dbms_lob.substr( p_json, 1, g_idx ) = c_end_brace; -- empty object or object with "trailing comma"
          copy_value; -- copy name
          skip_whitespace;
          if dbms_lob.substr( p_json, 1, g_idx ) != c_colon
          then
            raise_application_error( -20002, 'No valid JSON, expected a colon at position ' || g_idx );
          end if;
          append( g_idx, 1 );
          g_idx := g_idx + 1; -- skip colon
          copy_value; -- copy value
          skip_whitespace;
          case dbms_lob.substr( p_json, 1, g_idx )
            when c_comma then append( g_idx, 1 ); g_idx := g_idx + 1;
            when c_end_brace then exit;
            else raise_application_error( -20003, 'No valid JSON, expected a comma or end brace at position ' || g_idx );
          end case;
        end loop;
        append( g_idx, 1 );
        g_idx := g_idx + 1;
      end if;
    end;
--
    procedure copy_array
    is
    begin
      if dbms_lob.substr( p_json, 1, g_idx ) = c_start_bracket
      then
        append( g_idx, 1 );
        g_idx := g_idx + 1;
        loop
          skip_whitespace;
          exit when dbms_lob.substr( p_json, 1, g_idx ) = c_end_bracket; -- empty array or array with "trailing comma"
          copy_value;
          skip_whitespace;
          case dbms_lob.substr( p_json, 1, g_idx )
            when c_comma then append( g_idx, 1 ); g_idx := g_idx + 1;
            when c_end_bracket then exit;
            else raise_application_error( -20004, 'No valid JSON, expected a comma or end bracket at position ' || g_idx );
          end case;
        end loop;
        append( g_idx, 1 );
        g_idx := g_idx + 1;
      end if;
    end;
--
    procedure copy_value
    is
      l_start integer;
    begin
      skip_whitespace;
      l_start := g_idx;
      case dbms_lob.substr( p_json, 1, g_idx )
        when c_double_quote
        then
          loop
            g_idx := dbms_lob.instr( p_json, c_double_quote, g_idx + 1 );
            exit when dbms_lob.substr( p_json, 1, g_idx - 1 ) != c_back_slash
                   or g_idx = 0
                   or (   dbms_lob.substr( p_json, 2, g_idx - 2 ) = c_back_slash || c_back_slash
                      and dbms_lob.substr( p_json, 1, g_idx - 3 ) != c_back_slash
                      ); -- doesn't handle cases of values ending with multiple (escaped) \
          end loop;
          if g_idx = 0
          then
            raise_application_error( -20005, 'No valid JSON, no end string found' );
          end if;
          g_idx := g_idx + 1;
          append( l_start, g_idx - l_start );
        when c_single_quote  -- lax parsing
        then
          g_idx := dbms_lob.instr( p_json, c_single_quote, g_idx + 1 );
          if g_idx = 0
          then
            raise_application_error( -20006, 'No valid JSON, no end string found' );
          end if;
          g_idx := g_idx + 1;
          append( l_start, g_idx - l_start );
        when c_start_brace
        then
          copy_object;
        when c_start_bracket
        then
          copy_array;
        else -- should be a JSON-number, TRUE, FALSE or NULL, but we don't check for it
          g_idx := least( coalesce( nullif( instr( p_json, c_space, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_ht, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_cr, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_lf, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_comma, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_end_brace, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_end_bracket, g_idx ), 0 ), g_end  + 1 )
                        );
          if g_idx = g_end + 1
          then
            raise_application_error( -20007, 'No valid JSON, no end string found' );
          end if;
          append( l_start, g_idx - l_start );
      end case;
    end;
  begin
    if p_json is null
    then
      return null;
    end if;
    --
    g_idx := 1;
    g_end := dbms_lob.getlength( p_json );
    dbms_lob.createtemporary( l_rv, true );
    --
    skip_whitespace;
    if dbms_lob.substr( p_json, 1, g_idx ) in ( c_start_brace, c_start_bracket )
    then
      copy_value;
    end if;
    --
    return l_rv;
  end;
begin
  l_json := q'~{ "\"\\\" 15\u00f8C \u20ac 20" : 12   ,   'x' : [  true,null  , false,{  }  , [ ] ] }~';
  l_x := json_minifier( l_json );
  dbms_output.put_line( dbms_lob.getlength( l_x ) );
  dbms_output.put_line( l_x );
end;
/
