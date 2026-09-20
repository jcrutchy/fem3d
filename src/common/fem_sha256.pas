unit fem_sha256;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TSHA256Digest = array[0..31] of Byte;

function SHA256Bytes(const Data: TBytes): TSHA256Digest;
function SHA256File(const FileName: string): TSHA256Digest;
function DigestToHex(const D: TSHA256Digest): string;
function SHA256FileHex(const FileName: string): string;

implementation

const
  K: array[0..63] of UInt32 = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2
  );

function ROTR(x: UInt32; n: Byte): UInt32; inline;
begin
  Result := (x shr n) or (x shl (32 - n));
end;

function SHA256Bytes(const Data: TBytes): TSHA256Digest;
var
  HS: array[0..7] of UInt32;
  MsgLen, PaddedLen, NumBlocks, blk, i: Int64;
  t: Integer;
  Padded: TBytes;
  W: array[0..63] of UInt32;
  a, b, c, d, e, f, g, h, T1, T2, S0, S1, ch, maj: UInt32;
  BitLen: UInt64;
begin
  HS[0] := $6a09e667; HS[1] := $bb67ae85; HS[2] := $3c6ef372; HS[3] := $a54ff53a;
  HS[4] := $510e527f; HS[5] := $9b05688c; HS[6] := $1f83d9ab; HS[7] := $5be0cd19;

  MsgLen := Length(Data);
  BitLen := UInt64(MsgLen) * 8;

  PaddedLen := MsgLen + 1;
  while (PaddedLen mod 64) <> 56 do Inc(PaddedLen);
  PaddedLen := PaddedLen + 8;

  SetLength(Padded, PaddedLen);
  FillChar(Padded[0], PaddedLen, 0);
  if MsgLen > 0 then Move(Data[0], Padded[0], MsgLen);
  Padded[MsgLen] := $80;
  for i := 0 to 7 do
    Padded[PaddedLen - 1 - i] := Byte(BitLen shr (8 * i));

  NumBlocks := PaddedLen div 64;
  for blk := 0 to NumBlocks - 1 do
  begin
    for t := 0 to 15 do
      W[t] := (UInt32(Padded[blk * 64 + t * 4]) shl 24) or
              (UInt32(Padded[blk * 64 + t * 4 + 1]) shl 16) or
              (UInt32(Padded[blk * 64 + t * 4 + 2]) shl 8) or
               UInt32(Padded[blk * 64 + t * 4 + 3]);
    for t := 16 to 63 do
    begin
      S0 := ROTR(W[t - 15], 7) xor ROTR(W[t - 15], 18) xor (W[t - 15] shr 3);
      S1 := ROTR(W[t - 2], 17) xor ROTR(W[t - 2], 19) xor (W[t - 2] shr 10);
      W[t] := W[t - 16] + S0 + W[t - 7] + S1;
    end;

    a := HS[0]; b := HS[1]; c := HS[2]; d := HS[3];
    e := HS[4]; f := HS[5]; g := HS[6]; h := HS[7];

    for t := 0 to 63 do
    begin
      S1 := ROTR(e, 6) xor ROTR(e, 11) xor ROTR(e, 25);
      ch := (e and f) xor ((not e) and g);
      T1 := h + S1 + ch + K[t] + W[t];
      S0 := ROTR(a, 2) xor ROTR(a, 13) xor ROTR(a, 22);
      maj := (a and b) xor (a and c) xor (b and c);
      T2 := S0 + maj;
      h := g; g := f; f := e; e := d + T1;
      d := c; c := b; b := a; a := T1 + T2;
    end;

    HS[0] := HS[0] + a; HS[1] := HS[1] + b; HS[2] := HS[2] + c; HS[3] := HS[3] + d;
    HS[4] := HS[4] + e; HS[5] := HS[5] + f; HS[6] := HS[6] + g; HS[7] := HS[7] + h;
  end;

  for i := 0 to 7 do
  begin
    Result[i * 4]     := Byte(HS[i] shr 24);
    Result[i * 4 + 1] := Byte(HS[i] shr 16);
    Result[i * 4 + 2] := Byte(HS[i] shr 8);
    Result[i * 4 + 3] := Byte(HS[i]);
  end;
end;

function SHA256File(const FileName: string): TSHA256Digest;
var
  FS: TFileStream;
  Data: TBytes;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Data[0], FS.Size);
  finally
    FS.Free;
  end;
  Result := SHA256Bytes(Data);
end;

function DigestToHex(const D: TSHA256Digest): string;
const
  HexChars: array[0..15] of Char = '0123456789abcdef';
var
  i: Integer;
begin
  SetLength(Result, 64);
  for i := 0 to 31 do
  begin
    Result[i * 2 + 1] := HexChars[D[i] shr 4];
    Result[i * 2 + 2] := HexChars[D[i] and $0F];
  end;
end;

function SHA256FileHex(const FileName: string): string;
begin
  Result := DigestToHex(SHA256File(FileName));
end;

end.
