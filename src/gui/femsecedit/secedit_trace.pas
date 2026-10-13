unit secedit_trace;

// Diagnostic / error output for a GUI-subsystem program.
//
// femsecedit is built with -WG (GraphicApplication), so on Windows the Pascal
// text files StdErr / Output are NOT attached to anything: WriteLn(StdErr, ...)
// raises runtime error 103 (file not open). The standard OS handles are still
// valid when the parent redirected them (the test harness uses pipes), so
// WriteStdErr writes to those directly.
//
// Trace output is opt-in: set the environment variable FEMSECEDIT_TRACE to see
// what the window is doing on stderr. Costs nothing when it is not set.

{$mode objfpc}{$H+}

interface

// Writes S plus a line ending to stderr (falling back to stdout, then to
// nothing). Never raises.
procedure WriteStdErr(const S: string);

procedure Trace(const S: string);

implementation

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  SysUtils;

var
  Enabled: Boolean = False;
  Checked: Boolean = False;

{$IFDEF WINDOWS}
function WriteToStdHandle(StdId: DWORD; const Msg: AnsiString): Boolean;
var
  H: THandle;
  Written: DWORD;
begin
  Result := False;
  H := Windows.GetStdHandle(StdId);
  // 0 = no handle (GUI app started without redirection); -1 = invalid
  if (H = 0) or (H = INVALID_HANDLE_VALUE) then Exit;
  Result := Windows.WriteFile(H, Msg[1], Length(Msg), Written, nil);
end;
{$ENDIF}

procedure WriteStdErr(const S: string);
var
  Msg: AnsiString;
begin
  Msg := S + LineEnding;
  try
    {$IFDEF WINDOWS}
    if WriteToStdHandle(STD_ERROR_HANDLE, Msg) then Exit;
    if WriteToStdHandle(STD_OUTPUT_HANDLE, Msg) then Exit;
    {$ELSE}
    Write(StdErr, Msg);
    Flush(StdErr);
    {$ENDIF}
  except
    // diagnostics must never take the program down
  end;
end;

procedure Trace(const S: string);
begin
  if not Checked then
  begin
    Enabled := GetEnvironmentVariable('FEMSECEDIT_TRACE') <> '';
    Checked := True;
  end;
  if not Enabled then Exit;
  WriteStdErr('trace: ' + S);
end;

end.
