unit fem_fingerprint;

{$mode objfpc}{$H+}

// A model's "fingerprint": the SHA-256 of its CANONICAL text. A solver prints
// it with its results (MODEL.FINGERPRINT=...), and any viewer can recompute it
// from the model file it has been given and compare -- so results that were
// computed from an older version of the model are recognised as stale instead
// of being drawn on top of the wrong model.
//
// Canonical text (the rule is deliberately simple so it is trivial to repeat in
// any language -- viewer/js/femhash.js implements the very same rule):
//   1. A leading UTF-8 byte-order mark is dropped.
//   2. The text is split into lines at LF, CR LF or a lone CR.
//   3. In every line, leading and trailing spaces and tabs are removed.
//   4. Lines that are then empty, or that begin with '#', are dropped.
//   5. Each remaining line is written followed by one LF.
// The fingerprint is the lowercase hex SHA-256 of those bytes. So re-saving a
// file with different line endings, indentation, blank lines or comments does
// NOT change it, while changing any value, name, count or order of the data
// does. (It is a consistency check against stale or mismatched files, not a
// security feature: anyone can recompute it.)

interface

uses
  SysUtils, fem_sha256;

function CanonicalModelBytes(const Raw: TBytes): TBytes;
function ModelFingerprint(const Raw: TBytes): string;

implementation

function CanonicalModelBytes(const Raw: TBytes): TBytes;
var
  N, i, lineStart, lineEnd, a, b, outLen, startAt: Integer;
  OutBuf: TBytes;

  procedure Emit(s, e: Integer);  // bytes [s, e) of Raw, with spaces/tabs trimmed
  var
    k: Integer;
  begin
    while (s < e) and ((Raw[s] = 32) or (Raw[s] = 9)) do Inc(s);
    while (e > s) and ((Raw[e - 1] = 32) or (Raw[e - 1] = 9)) do Dec(e);
    if (e = s) or (Raw[s] = Ord('#')) then Exit;
    for k := s to e - 1 do
    begin
      OutBuf[outLen] := Raw[k];
      Inc(outLen);
    end;
    OutBuf[outLen] := 10;
    Inc(outLen);
  end;

begin
  N := Length(Raw);
  SetLength(OutBuf, N + 1);  // canonical text is never longer than the input + 1
  outLen := 0;
  startAt := 0;
  if (N >= 3) and (Raw[0] = $EF) and (Raw[1] = $BB) and (Raw[2] = $BF) then startAt := 3;
  lineStart := startAt;
  i := startAt;
  while i < N do
  begin
    if (Raw[i] = 10) or (Raw[i] = 13) then
    begin
      lineEnd := i;
      Emit(lineStart, lineEnd);
      if (Raw[i] = 13) and (i + 1 < N) and (Raw[i + 1] = 10) then Inc(i);
      lineStart := i + 1;
    end;
    Inc(i);
  end;
  if lineStart < N then Emit(lineStart, N);
  a := 0; b := outLen;
  Result := nil;
  SetLength(Result, b - a);
  if b > a then Move(OutBuf[0], Result[0], b - a);
end;

function ModelFingerprint(const Raw: TBytes): string;
begin
  Result := DigestToHex(SHA256Bytes(CanonicalModelBytes(Raw)));
end;

end.
