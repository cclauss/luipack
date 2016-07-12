unit HandlebarsScanner;

{$mode objfpc}{$H+}

interface

uses
  Classes;

type

  THandlebarsToken = (
    tkEOF,
    tkContent,
    tkOpenPartial,
    tkOpenPartialBlock,
    tkOpenBlock,
    tkOpenEndBlock,
    tkEndBlock,
    tkOpenRawBlock,
    tkCloseRawBlock,
    tkEndRawBlock,
    tkOpenBlockParams,
    tkCloseBlockParams,
    tkOpenSExpr,
    tkCloseSExpr,
    tkInverse,
    tkOpenInverse,
    tkOpenInverseChain,
    tkOpenUnescaped,
    tkCloseUnescaped,
    tkOpen,
    tkClose,
    tkComment,
    tkEquals,
    tkId,
    tkSep,
    tkData,
    tkBoolean,
    tkNumber,
    tkString,
    tkUndefined,
    tkNull,
    tkInvalid
  );

  //inspired by fpc jsonscanner

  { THandlebarsScanner }

  THandlebarsScanner = class
  private
     FSource : TStringList;
     FCurToken: THandlebarsToken;
     FCurTokenString: string;
     FCurLine: string;
     TokenStr: PChar;
     FCurRow: Integer;
     FMustacheLevel: Integer;
     function FetchLine: Boolean;
     function GetCurColumn: Integer;
     procedure ScanContent;
   protected
     procedure Error(const Msg: string);overload;
     procedure Error(const Msg: string; const Args: array of Const);overload;
   public
     constructor Create(Source : TStream); overload;
     constructor Create(const Source : String); overload;
     destructor Destroy; override;
     function FetchToken: THandlebarsToken;

     property CurLine: string read FCurLine;
     property CurRow: Integer read FCurRow;
     property CurColumn: Integer read GetCurColumn;

     property CurToken: THandlebarsToken read FCurToken;
     property CurTokenString: string read FCurTokenString;
   end;

implementation

{ THandlebarsScanner }

function THandlebarsScanner.FetchLine: Boolean;
begin
  Result := FCurRow < FSource.Count;
  if Result then
  begin
    FCurLine := FSource[FCurRow];
    TokenStr := PChar(FCurLine);
    Inc(FCurRow);
  end
  else
  begin
    FCurLine := '';
    TokenStr := nil;
  end;
end;

function THandlebarsScanner.GetCurColumn: Integer;
begin
  Result := TokenStr - PChar(CurLine);
end;

procedure THandlebarsScanner.ScanContent;
var
  TokenStart: PChar;
  SectionLength: Integer;
begin
  TokenStart := TokenStr;
  while True do
  begin
    Inc(TokenStr);
    SectionLength := TokenStr - TokenStart;
    if TokenStr[0] = #0 then
    begin
      if not FetchLine then
      begin
        SetLength(FCurTokenString, SectionLength);
        Move(TokenStart^, FCurTokenString[1], SectionLength);
        Break;
      end;
    end;
    if (TokenStr[0] = '{') and (TokenStr[1] = '{') then
    begin
      SetLength(FCurTokenString, SectionLength);
      Move(TokenStart^, FCurTokenString[1], SectionLength);
      Break;
    end;
  end;
end;

procedure THandlebarsScanner.Error(const Msg: string);
begin

end;

procedure THandlebarsScanner.Error(const Msg: string; const Args: array of const);
begin

end;

constructor THandlebarsScanner.Create(Source: TStream);
begin
  FSource := TStringList.Create;
  FSource.LoadFromStream(Source);
end;

constructor THandlebarsScanner.Create(const Source: String);
begin
  FSource := TStringList.Create;
  FSource.Text := Source;
end;

destructor THandlebarsScanner.Destroy;
begin
  FSource.Destroy;
  inherited Destroy;
end;

function GetNextToken(Start: PChar): PChar;
begin
  Result := Start;
  while Result[0] = ' ' do
    Inc(Result);
end;

function THandlebarsScanner.FetchToken: THandlebarsToken;
var
  TokenStart, NextToken: PChar;
  SectionLength, StrOffset: Integer;
  C, Escaped: Char;
begin
  if (TokenStr = nil) and not FetchLine then
  begin
    Result := tkEOF;
    FCurToken := Result;
    Exit;
  end;

  Result := tkInvalid;

  FCurTokenString := '';

  case TokenStr[0] of
    #0:         // Empty line
      begin
        if not FetchLine then
        begin
          Result := tkEOF;
        end;
      end;
    '{':
      begin
        //{{
        TokenStart := TokenStr;
        if TokenStr[1] = '{' then
        begin
          Result := tkOpen;
          Inc(TokenStr, 2);
          case TokenStr[0] of
            '>': Result := tkOpenPartial;
            '#':
              begin
                if TokenStr[1] = '>' then
                begin
                  Result := tkOpenPartialBlock;
                  Inc(TokenStr);
                end
                else
                  Result := tkOpenBlock;
              end;
            '/': Result := tkOpenEndBlock;
            '&': Inc(TokenStr);
            '{': Result := tkOpenUnescaped;
            '^':
              begin
                NextToken := GetNextToken(TokenStr + 1);
                if (NextToken[0] = '}') and (NextToken[1] = '}') then
                begin
                  Result := tkInverse;
                  TokenStr := NextToken;
                  Inc(TokenStr, 2);
                end
                else
                  Result := tkOpenInverse;
              end;
          end;
          NextToken := GetNextToken(TokenStr);
          if (NextToken[0] = 'e') and (NextToken[1] = 'l') and (NextToken[2] = 's') and (NextToken[3] = 'e') then
          begin
            NextToken := GetNextToken(NextToken + 4);
            if (NextToken[0] = '}') and (NextToken[1] = '}') then
            begin
              Result := tkInverse;
              TokenStr := NextToken;
              Inc(TokenStr, 2);
            end;
          end;
          if Result <> tkInverse then
          begin
            if Result <> tkOpen then
              Inc(TokenStr);
            Inc(FMustacheLevel);
          end;
          SectionLength := TokenStr - TokenStart;
          SetLength(FCurTokenString, SectionLength);
          Move(TokenStart^, FCurTokenString[1], SectionLength);
        end
        else
        begin
          Result := tkContent;
          ScanContent;
        end;
      end;
    '}':
      begin
        TokenStart := TokenStr;
        if (TokenStr[1] = '}') and (FMustacheLevel > 0) then
        begin
          if TokenStr[2] = '}' then
          begin
            Result := tkCloseUnescaped;
            Inc(TokenStr, 3);
          end
          else
          begin
            Result := tkClose;
            Inc(TokenStr, 2);
          end;
          SectionLength := TokenStr - TokenStart;
          SetLength(FCurTokenString, SectionLength);
          Move(TokenStart^, FCurTokenString[1], SectionLength);
          Dec(FMustacheLevel);
        end
        else
        begin
          Result := tkContent;
          ScanContent;
        end;
      end;
  else
    if FMustacheLevel = 0 then
    begin
      Result := tkContent;
      ScanContent;
    end
    else
    begin
      while TokenStr[0] = ' ' do
        Inc(TokenStr);
      StrOffset := 0;
      TokenStart := TokenStr;
      case TokenStr[0] of
        '/':
          begin
            Result := tkSep;
            Inc(TokenStr);
          end;
        '.':
          begin
            Result := tkSep;
            if TokenStr[1] = '.' then
            begin
              Result := tkId;
              Inc(TokenStr);
            end else if FCurToken <> tkId then
              Result := tkId;
            Inc(TokenStr);
          end;
        '"', '''':
          begin
            Result := tkString;
            C := TokenStr[0];
            Inc(TokenStr);
            TokenStart := TokenStr;
            while not (TokenStr[0] in [#0, C]) do
            begin
              if (TokenStr[0] = '\') then
              begin
                // Save length
                SectionLength := TokenStr - TokenStart;
                Inc(TokenStr);
                // Read escaped token
                case TokenStr[0] of
                  '"' : Escaped:='"';
                  '''': Escaped:='''';
                  't' : Escaped:=#9;
                  'b' : Escaped:=#8;
                  'n' : Escaped:=#10;
                  'r' : Escaped:=#13;
                  'f' : Escaped:=#12;
                  '\' : Escaped:='\';
                  '/' : Escaped:='/';
                  #0  : Error('SErrOpenString');
                else
                  Error('SErrInvalidCharacter', [CurRow,CurColumn,TokenStr[0]]);
                end;
                SetLength(FCurTokenString, StrOffset + SectionLength + 2);
                if SectionLength > 0 then
                  Move(TokenStart^, FCurTokenString[StrOffset + 1], SectionLength);
                FCurTokenString[StrOffset + SectionLength + 1] := Escaped;
                Inc(StrOffset, SectionLength + 1);
                // Next char
                // Inc(TokenStr);
                TokenStart := TokenStr + 1;
              end;
              if TokenStr[0] = #0 then
                Error('SErrOpenString');
              Inc(TokenStr);
            end;
            if TokenStr[0] = #0 then
              Error('SErrOpenString');
          end;
      else
        Result := tkId;
        while True do
        begin
          if TokenStr[0] = #0 then
          begin
            if not FetchLine then
            begin
              SectionLength := TokenStr - TokenStart;
              SetLength(FCurTokenString, SectionLength);
              Move(TokenStart^, FCurTokenString[1], SectionLength);
              Break;
            end;
          end;
          if ((TokenStr[0] = '}') and (TokenStr[1] = '}')) or (TokenStr[0] in [' ', '.', '/']) then
            break;
          Inc(TokenStr);
        end;
      end;
      SectionLength := TokenStr - TokenStart;
      SetLength(FCurTokenString, SectionLength + StrOffset);
      if SectionLength > 0 then
        Move(TokenStart^, FCurTokenString[StrOffset + 1], SectionLength);
      if Result = tkString then
        Inc(TokenStr);
      //rigth trim space
      while TokenStr[0] = ' ' do
        Inc(TokenStr);
    end;
  end;

  FCurToken := Result;
end;

end.
