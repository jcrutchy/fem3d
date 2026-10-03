program fingerprint_test;

// The model fingerprint (fem_fingerprint): SHA-256 of a canonical form of the
// model text. These checks pin down exactly which edits must NOT change it
// (line endings, indentation, blank lines, comments, a byte-order mark) and
// which MUST (any value, name or ordering change), plus SHA-256 test vectors
// so a broken hash cannot hide behind consistent-but-wrong comparisons.
// Exit code 0 = all passed.

{$mode objfpc}{$H+}

uses
  SysUtils, fem_sha256, fem_fingerprint;

var
  Fails, Checks: Integer;

procedure Check(const Name: string; Ok: Boolean; const Detail: string = '');
begin
  Inc(Checks);
  if Ok then WriteLn('PASS  ', Name)
  else begin Inc(Fails); WriteLn('FAIL  ', Name, '  ', Detail); end;
end;

function B(const S: string): TBytes;
begin
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

function FP(const S: string): string;
begin
  Result := ModelFingerprint(B(S));
end;

function RawHex(const S: string): string;
begin
  Result := DigestToHex(SHA256Bytes(B(S)));
end;

const
  Base = '[NODES]' + #10 + '1, 0, 0, 0' + #10 + '2, 1, 0, 0' + #10 + #10 + '[ELEMENTS]' + #10 + '1, truss, 1, 2, 1' + #10;

begin
  Fails := 0; Checks := 0;

  // SHA-256 known-answer tests (FIPS 180-2 examples and the empty string)
  Check('SHA-256 of the empty string',
    RawHex('') = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  Check('SHA-256 of "abc"',
    RawHex('abc') = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  Check('SHA-256 of the 448-bit message',
    RawHex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') =
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');

  // the canonical form itself
  Check('canonical text of a simple file is the trimmed non-comment lines, LF-terminated',
    DigestToHex(SHA256Bytes(CanonicalModelBytes(B('  # c' + #13#10 + ' a,b  ' + #9 + #13#10 + #13#10 + 'c' + #13)))) = RawHex('a,b' + #10 + 'c' + #10));

  // must NOT change the fingerprint
  Check('CRLF line endings give the same fingerprint',
    FP(StringReplace(Base, #10, #13#10, [rfReplaceAll])) = FP(Base));
  Check('lone-CR line endings give the same fingerprint',
    FP(StringReplace(Base, #10, #13, [rfReplaceAll])) = FP(Base));
  Check('indentation and trailing spaces/tabs do not matter',
    FP(StringReplace(Base, #10, ' ' + #9 + #10 + '    ', [rfReplaceAll])) = FP(Base));
  Check('extra blank lines do not matter', FP(#10#10 + StringReplace(Base, #10, #10#10#10, [rfReplaceAll])) = FP(Base));
  Check('comments (whole-line #) do not matter',
    FP('# header comment' + #10 + Base + '# trailing comment' + #10 + '   # indented comment' + #10) = FP(Base));
  Check('a missing final newline does not matter', FP(Copy(Base, 1, Length(Base) - 1)) = FP(Base));
  Check('a UTF-8 byte-order mark does not matter', FP(#$EF#$BB#$BF + Base) = FP(Base));

  // MUST change it
  Check('changing a coordinate changes the fingerprint', FP(StringReplace(Base, '2, 1, 0, 0', '2, 1.0001, 0, 0', [])) <> FP(Base));
  Check('changing an id changes the fingerprint', FP(StringReplace(Base, '2, 1, 0, 0', '3, 1, 0, 0', [])) <> FP(Base));
  Check('reordering lines changes the fingerprint',
    FP('[NODES]' + #10 + '2, 1, 0, 0' + #10 + '1, 0, 0, 0' + #10 + #10 + '[ELEMENTS]' + #10 + '1, truss, 1, 2, 1' + #10) <> FP(Base));
  Check('internal spacing inside a line IS significant (documented: only the ends are trimmed)',
    FP(StringReplace(Base, '1, 0, 0, 0', '1,  0, 0, 0', [])) <> FP(Base));
  Check('the empty file has a defined fingerprint (SHA-256 of nothing)',
    FP('') = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  Check('a "#" that is not at the start of the line is data, not a comment',
    FP('1, 2 # not a comment' + #10) <> FP('1, 2' + #10));

  WriteLn;
  if Fails = 0 then begin WriteLn('ALL ', Checks, ' CHECKS PASSED'); Halt(0); end
  else begin WriteLn(Fails, ' of ', Checks, ' CHECKS FAILED'); Halt(1); end;
end.
