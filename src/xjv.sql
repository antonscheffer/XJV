declare
--
  function xjv
    ( p_json varchar2 character set any_cs
    , p_path varchar2
    , p_unescape varchar2 := 'Y'
    )
  return varchar2 character set p_json%charset
  is
    c_double_quote  constant varchar2(1) character set p_json%charset := '"';
    c_single_quote  constant varchar2(1) character set p_json%charset := '''';
    c_back_slash    constant varchar2(1) character set p_json%charset := '\';
    c_space         constant varchar2(1) character set p_json%charset := ' ';
    c_colon         constant varchar2(1) character set p_json%charset := ':';
    c_comma         constant varchar2(1) character set p_json%charset := ',';
    c_end_brace     constant varchar2(1) character set p_json%charset := '}';
    c_start_brace   constant varchar2(1) character set p_json%charset := '{';
    c_end_bracket   constant varchar2(1) character set p_json%charset := ']';
    c_start_bracket constant varchar2(1) character set p_json%charset := '[';
    c_ht            constant varchar2(1) character set p_json%charset := chr(9);
    c_lf            constant varchar2(1) character set p_json%charset := chr(10);
    c_cr            constant varchar2(1) character set p_json%charset := chr(13);
    c_ws            constant varchar2(4) character set p_json%charset := c_space || c_ht || c_cr || c_lf;
--
    g_idx number;
    g_end number;
--
    l_nchar boolean := isnchar( c_space );
    l_pos number;
    l_ind number;
    l_start number;
    l_rv_end number;
    l_rv_start number;
    l_path varchar2(32767);
    l_name varchar2(32767);
    l_tmp_name varchar2(32767);
    l_rv varchar2(32767) character set p_json%charset;
    l_chr varchar2(10) character set p_json%charset;
--
    procedure skip_whitespace
    is
    begin
      while substr( p_json, g_idx, 1 ) in ( c_space, c_lf, c_cr, c_ht )
      loop
        g_idx:= g_idx+ 1;
      end loop;
      if g_idx > g_end
      then
        raise_application_error( -20001, 'Unexpected end of JSON' );
      end if;
    end;
--
    procedure skip_value;
    procedure skip_array;
--
    procedure skip_object
    is
    begin
      if substr( p_json, g_idx, 1 ) = c_start_brace
      then
        g_idx := g_idx + 1;
        loop
          skip_whitespace;
          exit when substr( p_json, g_idx, 1 ) = c_end_brace; -- empty object or object with "trailing comma"
          skip_value; -- skip name
          skip_whitespace;
          if substr( p_json, g_idx, 1 ) != c_colon
          then
            raise_application_error( -20002, 'No valid JSON, expected a colon at position ' || g_idx );
          end if;
          g_idx := g_idx + 1; -- skip colon
          skip_value; -- skip value
          skip_whitespace;
          case substr( p_json, g_idx, 1 )
            when c_comma then g_idx := g_idx + 1;
            when c_end_brace then exit;
            else raise_application_error( -20003, 'No valid JSON, expected a comma or end brace at position ' || g_idx );
          end case;
        end loop;
        g_idx := g_idx + 1;
      end if;
    end;
--
    procedure skip_array
    is
    begin
      if substr( p_json, g_idx, 1 ) = c_start_bracket
      then
        g_idx := g_idx + 1;
        loop
          skip_whitespace;
          exit when substr( p_json, g_idx, 1 ) = c_end_bracket; -- empty array or array with "trailing comma"
          skip_value;
          skip_whitespace;
          case substr( p_json, g_idx, 1 )
            when c_comma then g_idx := g_idx + 1;
            when c_end_bracket then exit;
            else raise_application_error( -20004, 'No valid JSON, expected a comma or end bracket at position ' || g_idx );
          end case;
        end loop;
        g_idx := g_idx + 1;
      end if;
    end;
--
    procedure skip_value
    is
    begin
      skip_whitespace;
      case substr( p_json, g_idx, 1 )
        when c_double_quote
        then
          loop
            g_idx := instr( p_json, c_double_quote, g_idx + 1 );
            exit when substr( p_json, g_idx - 1, 1 ) != c_back_slash
                   or g_idx = 0
                   or (   substr( p_json, g_idx - 2, 2 ) = c_back_slash || c_back_slash
                      and substr( p_json, g_idx - 3, 1 ) != c_back_slash
                      ); -- doesn't handle cases of values ending with multiple (escaped) \
          end loop;
          if g_idx = 0
          then
            raise_application_error( -20005, 'No valid JSON, no end string found' );
          end if;
          g_idx := g_idx + 1;
        when c_single_quote
        then
          g_idx := instr( p_json, c_single_quote, g_idx ) + 1;
          if g_idx = 1
          then
            raise_application_error( -20006, 'No valid JSON, no end string found' );
          end if;
        when c_start_brace
        then
          skip_object;
        when c_start_bracket
        then
          skip_array;
        else -- should be a JSON-number, TRUE, FALSE or NULL, but we don't check for it
          g_idx := least( coalesce( nullif( instr( p_json, c_space, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_comma, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_end_brace, g_idx ), 0 ), g_end + 1 )
                        , coalesce( nullif( instr( p_json, c_end_bracket, g_idx ), 0 ), g_end  + 1)
                        , coalesce( nullif( instr( p_json, c_colon, g_idx ), 0 ), g_end + 1 )
                        );
          if g_idx = g_end + 1
          then
            raise_application_error( -20007, 'No valid JSON, no end string found' );
          end if;
      end case;
    end;
  begin
    if p_json is null
    then
      return null;
    end if;
    l_path := ltrim( p_path, c_ws );
    if l_path is null
    then
      return null;
    end if;
    g_idx := 1;
    g_end := length( p_json );
    for i in 1 .. 20 -- max 20 levels deep in p_path
    loop
      l_path := ltrim( l_path, c_ws );
      l_pos := least( nvl( nullif( instr( l_path, '.' ), 0 ), 32768 )
                    , nvl( nullif( instr( l_path, c_start_bracket ), 0 ), 32768 )
                    , nvl( nullif( instr( l_path, c_end_bracket ), 0 ), 32768 )
                    );
      if l_pos = 32768
      then
        l_name := l_path;
        l_path := null;
      elsif substr( l_path, l_pos, 1 ) = '.'
      then
        l_name := substr( l_path, 1, l_pos - 1 );
        l_path := substr( l_path, l_pos + 1 );
      elsif substr( l_path, l_pos, 1 ) = c_start_bracket and l_pos > 1
      then
        l_name := substr( l_path, 1, l_pos - 1 );
        l_path := substr( l_path, l_pos );
      elsif substr( l_path, l_pos, 1 ) = c_start_bracket and l_pos = 1
      then
        l_pos := instr( l_path, c_end_bracket );
        if l_pos = 0
        then
          raise_application_error( -20008, 'No valid path, end bracket expected' );
        end if;
        l_name := substr( l_path, 1, l_pos );
        if substr( l_path, l_pos + 1, 1 ) = '.'
        then
          l_path := substr( l_path, l_pos + 2 );
        else
          l_path := substr( l_path, l_pos + 1 );
        end if;
      end if;
      l_name := rtrim( l_name, c_ws );
--
      skip_whitespace;
      if substr( p_json, g_idx, 1 ) = c_start_brace and substr( l_name, 1, 1 ) != c_start_bracket
      then -- search for a name inside JSON object
           -- json unescape name?
        loop
          g_idx := g_idx + 1; -- skip start brace or comma
          skip_whitespace;
          if substr( p_json, g_idx, 1 ) = c_end_brace
          then
            return null;
          end if;
          l_start := g_idx;
          skip_value;  -- skip a name
          l_tmp_name := substr( p_json, l_start, g_idx - l_start ); -- look back to get the name skipped
           -- json unescape name?
          skip_whitespace;
          if substr( p_json, g_idx, 1 ) != c_colon
          then
            raise_application_error( -20002, 'No valid JSON, expected a colon at position ' || g_idx );
          end if;
          g_idx := g_idx + 1;  -- skip colon
          skip_whitespace;
          l_rv_start := g_idx;
          skip_value;
          if l_tmp_name in ( c_double_quote || l_name || c_double_quote
                           , c_single_quote || l_name || c_single_quote
                           , l_name
                           )
          then
            l_rv_end := g_idx;
            exit;
          else
            skip_whitespace;
            if substr( p_json, g_idx, 1 ) = c_comma
            then
              null; -- OK, keep on searching for name
            else
              return null; -- searched name not found
            end if;
          end if;
        end loop;
      elsif substr( p_json, g_idx, 1 ) = c_start_bracket and substr( l_name, 1, 1 ) = c_start_bracket
      then
        begin
          l_ind := to_number( rtrim( ltrim( l_name, c_start_bracket ), c_end_bracket ) );
        exception
          when value_error
          then
            raise_application_error( -20009, 'No valid path, array index number expected' );
        end;
        for i in 0 .. l_ind loop
          g_idx := g_idx + 1; -- skip start bracket or comma
          skip_whitespace;
          if substr( p_json, g_idx, 1 ) = c_end_bracket
          then
            return null;
          end if;
          l_rv_start := g_idx;
          skip_value;
          if i = l_ind
          then
            l_rv_end := g_idx;
            exit;
          else
            skip_whitespace;
            if substr( p_json, g_idx, 1 ) = c_comma
            then
              null; -- OK
            else
              return null;
            end if;
          end if;
        end loop;
      else
        return null;
      end if;
      exit when l_path is null;
      g_idx := l_rv_start;
      g_end := l_rv_end - 1;
    end loop;
    if (  (   substr( p_json, l_rv_start, 1 ) = c_double_quote
          and substr( p_json, l_rv_end - 1, 1 ) = c_double_quote
          )
       or (   substr( p_json, l_rv_start, 1 ) = c_single_quote
          and substr( p_json, l_rv_end - 1, 1 ) = c_single_quote
          )
       )
    then
      l_rv_start := l_rv_start + 1;
      l_rv_end := l_rv_end - 1;
    end if;
    l_pos := instr( p_json, c_back_slash, l_rv_start );
    if l_pos = 0 or l_pos >= l_rv_end or nvl( substr( upper( p_unescape ), 1, 1 ), 'Y' ) = 'N'
    then -- no JSON unescaping needed
      return substr( p_json, l_rv_start, l_rv_end - l_rv_start );
    end if;
    l_start := l_rv_start;
    loop
      l_chr := substr( p_json, l_pos + 1, 1 );
      if l_chr in ( '"', '\', '/' )
      then
        l_rv := l_rv || ( substr( p_json, l_start, l_pos - l_start ) || l_chr );
      elsif l_chr in ( 'b', 'f', 'n', 'r', 't' )
      then
        l_chr := translate( l_chr
                          , 'btnfr'
                          , chr(8) || chr(9) || chr(10) || chr(12) || chr(13)
                          );
        l_rv := l_rv || ( substr( p_json, l_start, l_pos - l_start ) || l_chr );
      elsif l_chr = 'u'
      then -- unicode character
        if l_nchar
        then
          l_chr := utl_i18n.raw_to_nchar( hextoraw( substr( p_json, l_pos + 2, 4 ) ), 'AL16UTF16' );
        else
          l_chr := utl_i18n.raw_to_char( hextoraw( substr( p_json, l_pos + 2, 4 ) ), 'AL16UTF16' );
        end if;
        l_rv := l_rv || ( substr( p_json, l_start, l_pos - l_start ) || l_chr );
        l_pos := l_pos + 4;
      else
        raise_application_error( -20011, 'No valid JSON, unexpected back slash  at position ' || l_pos );
      end if;
      l_start := l_pos + 2;
      l_pos := instr( p_json, c_back_slash, l_start );
      if l_pos = 0 or l_pos >= l_rv_end
      then
        l_rv := l_rv || substr( p_json, l_start, l_rv_end - l_start );
        exit;
      end if;
    end loop;
    return l_rv;
  end;
begin
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"de"}}', 'a' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"de"}}', 'b' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"de"}}', 'c' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"de"}}', 'd.e' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":[],"d":[{"e":"de"},true,null]}', 'c' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":[],"d":[{"e":"de"},true,null]}', 'd[0]' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":[],"d":[{"e":"de"},true,null]}', 'd[1]' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":[],"d":[{"e":"de"},true,null]}', 'd[2]' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"\"\\\""}}', 'd.e' ) );
  dbms_output.put_line( xjv( '{"a":"A","b":"BB","c":{},"d":{"e":"\"\\\" 15\u00f8C \u20ac 20"}}', 'd.e' )  );
  dbms_output.put_line( xjv( '{"a":{"b":[{},{},{"c":[0,1,2,3,4]}]}}', 'a.b[2].c[3]' )  );
end;
