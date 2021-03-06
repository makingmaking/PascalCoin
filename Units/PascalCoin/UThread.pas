unit UThread;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{ Copyright (c) 2016 by Albert Molina

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This unit is a part of Pascal Coin, a P2P crypto currency without need of
  historical operations.

  If you like it, consider a donation using BitCoin:
  16K3HCZRhFUtM8GdWRcfKeaa6KsuyxZaYk

  }

interface

uses
{$IFnDEF FPC}
  Windows,
{$ELSE}
  {$IFDEF LINUX}cthreads,{$ENDIF}
{$ENDIF}
  Classes, SyncObjs;

Type
  TPCCriticalSection = Class(TCriticalSection)
  private
    FCounterLock : TCriticalSection;
    FWaitingForCounter : Integer;
    FCurrentThread : Cardinal;
    FStartedTimestamp : Cardinal;
    FName : String;
  public
    Constructor Create(const AName : String);
    Destructor Destroy; override;
    procedure Acquire; override;
    procedure Release; override;
    function TryEnter: Boolean;
    Property CurrentThread : Cardinal read FCurrentThread;
    Property WaitingForCounter : Integer read FWaitingForCounter;
    Property StartedTimestamp : Cardinal read FStartedTimestamp;
    Property Name : String read FName;
  end;

  TPCThread = Class;
  TPCThreadClass = Class of TPCThread;
  TPCThread = Class(TThread)
  private
    FDebugStep: String;
    FStartTickCount : Cardinal;
  protected
    procedure DoTerminate; override;
    procedure Execute; override;
    procedure BCExecute; virtual; abstract;
  public
    Class function ThreadClassFound(tclass : TPCThreadClass; Exclude : TObject) : Integer;
    Class function ThreadCount : Integer;
    Class function GetThread(index : Integer) : TPCThread;
    Class function GetThreadByClass(tclass : TPCThreadClass; Exclude : TObject) : TPCThread;
    Class function TerminateAllThreads(tclass: TPCThreadClass) : Integer;
    Class Procedure ProtectEnterCriticalSection(Const Sender : TObject; var Lock : TPCCriticalSection);
    Class Function TryProtectEnterCriticalSection(Const Sender : TObject; MaxWaitMilliseconds : Cardinal; var Lock : TPCCriticalSection) : Boolean;
    Class Procedure ThreadsListInfo(list: TStrings);
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;
    Property DebugStep : String read FDebugStep write FDebugStep;
    property Terminated;
  End;

  TPCThreadList = class
  private
    FList: TList;
    FLock: TPCCriticalSection;
  public
    constructor Create(const AName : String);
    destructor Destroy; override;
    function Add(Item: Pointer) : Integer;
    procedure Clear;
    procedure Remove(Item: Pointer); inline;
    function LockList: TList;
    function TryLockList(MaxWaitMilliseconds : Cardinal; var lockedList : TList) : Boolean;
    procedure UnlockList; inline;
  end;


implementation

uses
  SysUtils, ULog, UConst;

{ TPCThread }

Var _threads : TPCThreadList;

constructor TPCThread.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);
  TLog.NewLog(ltdebug,Classname,'Created Thread '+IntToHex(PtrInt(Self),8));
end;

destructor TPCThread.Destroy;
begin
  inherited;
end;

procedure TPCThread.DoTerminate;
begin
  inherited;
end;

procedure TPCThread.Execute;
Var l : TList;
  i : Integer;
begin
  FStartTickCount := GetTickCount;
  FDebugStep := '';
  i := _threads.Add(Self);
  try
    TLog.NewLog(ltdebug,Classname,'Starting Thread '+IntToHex(PtrInt(Self),8)+' in pos '+inttostr(i+1));
    Try
      Try
        BCExecute;
        FDebugStep := 'Finalized BCExecute';
      Finally
        Terminate;
      End;
    Except
      On E:Exception do begin
        TLog.NewLog(lterror,Classname,'Exception inside a Thread at step: '+FDebugStep+' ('+E.ClassName+'): '+E.Message);
        Raise;
      end;
    End;
  finally
    l := _threads.LockList;
    Try
      i := l.Remove(Self);
      TLog.NewLog(ltdebug,Classname,'Finalizing Thread in pos '+inttostr(i+1)+'/'+inttostr(l.Count+1)+' working time: '+FormatFloat('0.000',(GetTickCount-FStartTickCount) / 1000)+' sec');
    Finally
      _threads.UnlockList;
    End;
  end;
end;

class function TPCThread.GetThread(index: Integer): TPCThread;
Var l : TList;
begin
  Result := Nil;
  l := _threads.LockList;
  try
    if (index<0) or (index>=l.Count) then exit;
    Result := TPCThread(l[index]);
  finally
    _threads.UnlockList;
  end;
end;

class function TPCThread.GetThreadByClass(tclass: TPCThreadClass; Exclude: TObject): TPCThread;
Var l : TList;
  i : Integer;
begin
  Result := Nil;
  if Not Assigned(_threads) then exit;
  l := _threads.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if (TPCThread(l[i]) is tclass) And ((l[i])<>Exclude) then begin
        Result := TPCThread(l[i]);
        exit;
      end;
    end;
  finally
    _threads.UnlockList;
  end;
end;

class procedure TPCThread.ProtectEnterCriticalSection(Const Sender : TObject; var Lock: TPCCriticalSection);
begin

  if Not Lock.TryEnter then begin
//    TLog.NewLog(ltdebug,Sender.Classname,Format('Locked critical section (WAIT): LockCount:%d RecursionCount:%d Semaphore:%d LockOwnerThread:%s',[
//      Lock.LockCount,Lock.RecursionCount,Lock.LockSemaphore,IntToHex(Lock.OwningThread,8) ]));
    Lock.Acquire;
//    TLog.NewLog(ltdebug,Sender.Classname,Format('UnLocked critical section (ENTER): LockCount:%d RecursionCount:%d Semaphore:%d LockOwnerThread:%s',[
//      Lock.LockCount,Lock.RecursionCount,Lock.LockSemaphore,IntToHex(Lock.OwningThread,8) ]));
  end;
end;

class function TPCThread.TerminateAllThreads(tclass: TPCThreadClass): Integer;
begin

end;

class function TPCThread.ThreadClassFound(tclass: TPCThreadClass; Exclude : TObject): Integer;
Var l : TList;
begin
  Result := -1;
  if Not Assigned(_threads) then exit;
  l := _threads.LockList;
  try
    for Result := 0 to l.Count - 1 do begin
      if (TPCThread(l[Result]) is tclass) And ((l[Result])<>Exclude) then exit;
    end;
    Result := -1;
  finally
    _threads.UnlockList;
  end;
end;

class function TPCThread.ThreadCount: Integer;
Var l : TList;
begin
  l := _threads.LockList;
  try
    Result := l.Count;
  finally
    _threads.UnlockList;
  end;
end;

class procedure TPCThread.ThreadsListInfo(list: TStrings);
Var l : TList;
  i : Integer;
begin
  l := _threads.LockList;
  try
    list.BeginUpdate;
    list.Clear;
    for i := 0 to l.Count - 1 do begin
      list.Add(Format('%.2d/%.2d <%s> Time:%s sec - Step: %s',[i+1,l.Count,TPCThread(l[i]).ClassName,FormatFloat('0.000',(GetTickCount-TPCThread(l[i]).FStartTickCount) / 1000),TPCThread(l[i]).DebugStep] ));
    end;
    list.EndUpdate;
  finally
    _threads.UnlockList;
  end;
end;

class function TPCThread.TryProtectEnterCriticalSection(const Sender: TObject;
  MaxWaitMilliseconds: Cardinal; var Lock: TPCCriticalSection): Boolean;
Var tc,tc2,tc3,lockCurrThread,lockWatingForCounter,lockStartedTimestamp : Cardinal;
  s : String;
begin
  tc := GetTickCount;
  if MaxWaitMilliseconds>60000 then MaxWaitMilliseconds := 60000;
  lockWatingForCounter := Lock.WaitingForCounter;
  lockStartedTimestamp := Lock.StartedTimestamp;
  lockCurrThread := Lock.CurrentThread;
  Repeat
    Result := Lock.TryEnter;
    if Not Result then sleep(1);
  Until (Result) Or (GetTickCount > (tc + MaxWaitMilliseconds));
  if Not Result then begin
    tc2 := GetTickCount;
    if lockStartedTimestamp=0 then lockStartedTimestamp := Lock.StartedTimestamp;
    if lockStartedTimestamp=0 then tc3 := 0
    else tc3 := tc2-lockStartedTimestamp;
    s := Format('Cannot Protect a critical section %s %s class %s after %d milis locked by %s waiting %d-%d elapsed milis: %d',
      [IntToHex(PtrInt(Lock),8),Lock.Name,
      Sender.ClassName,tc2-tc,
      IntToHex(lockCurrThread,8)+'-'+IntToHex(Lock.CurrentThread,8),
      lockWatingForCounter,Lock.WaitingForCounter,
      tc3
      ]);
    TLog.NewLog(ltdebug,Classname,s);
  end;
end;

{ TPCThreadList }

function TPCThreadList.Add(Item: Pointer) : Integer;
begin
  LockList;
  Try
    Result := FList.Add(Item);
  Finally
    UnlockList;
  End;
end;

procedure TPCThreadList.Clear;
begin
  LockList;
  Try
    FList.Clear;
  Finally
    UnlockList;
  End;
end;

constructor TPCThreadList.Create(const AName : String);
begin
  FLock := TPCCriticalSection.Create(AName);
  FList := TList.Create;
end;

destructor TPCThreadList.Destroy;
begin
  LockList;
  try
    FreeAndNil(FList);
    inherited Destroy;
  finally
    UnlockList;
    FreeAndNil(FLock);
  end;
end;

function TPCThreadList.LockList: TList;
begin
  TPCThread.ProtectEnterCriticalSection(Self,FLock);
  Result := FList;
end;

procedure TPCThreadList.Remove(Item: Pointer);
begin
  LockList;
  try
    FList.Remove(Item);
  finally
    UnlockList;
  end;
end;

function TPCThreadList.TryLockList(MaxWaitMilliseconds: Cardinal;
  var lockedList: TList): Boolean;
begin
  lockedList := FList;
  Result := TPCThread.TryProtectEnterCriticalSection(Self,MaxWaitMilliseconds,FLock);
end;

procedure TPCThreadList.UnlockList;
begin
  FLock.Release;
end;

{ TPCCriticalSection }

procedure TPCCriticalSection.Acquire;
Var continue, logged : Boolean;
  startTC : Cardinal;
begin
  startTC := GetTickCount;
  FCounterLock.Acquire;
  try
    FWaitingForCounter := FWaitingForCounter + 1;
  finally
    FCounterLock.Release;
  end;
  logged := false;
  Repeat
    continue := inherited TryEnter;
    if (Not continue) then begin
      If (not logged) And ((FStartedTimestamp>0) And ((FStartedTimestamp+1000)<GetTickCount)) then begin
        logged := true;
        TLog.NewLog(ltdebug,ClassName,'ALERT Critical section '+IntToHex(PtrInt(Self),8)+' '+Name+
          ' locked by '+IntToHex(FCurrentThread,8)+' waiting '+
          IntToStr(FWaitingForCounter)+' elapsed milis: '+IntToStr(GetTickCount-FStartedTimestamp) );
        continue := true;
        inherited;
      end else sleep(1);
    end;
  Until continue;
  if (logged) then begin
    TLog.NewLog(ltdebug,Classname,'ENTER Critical section '+IntToHex(PtrInt(Self),8)+' '+Name+' elapsed milis: '+IntToStr(GetTickCount - startTC) );
  end;
  FCounterLock.Acquire;
  try
    FWaitingForCounter := FWaitingForCounter - 1;
  finally
    FCounterLock.Release;
  end;
  FCurrentThread := TThread.CurrentThread.ThreadID;
  FStartedTimestamp := GetTickCount;
end;

constructor TPCCriticalSection.Create(const AName : String);
begin
  FCounterLock := TCriticalSection.Create;
  FWaitingForCounter := 0;
  FCurrentThread := 0;
  FStartedTimestamp := 0;
  FName := AName;
  inherited Create;
  // XXXXX DEBUG ONLY
  // TLog.NewLog(ltDebug,ClassName,'Created critical section '+IntToHex(PtrInt(Self),8)+' '+AName );
end;

destructor TPCCriticalSection.Destroy;
begin
  FCounterLock.Free;
  inherited;
end;

procedure TPCCriticalSection.Release;
begin
  FCurrentThread := 0;
  FStartedTimestamp := 0;
  inherited;
end;

function TPCCriticalSection.TryEnter: Boolean;
begin
  FCounterLock.Acquire;
  try
    FWaitingForCounter := FWaitingForCounter + 1;
  finally
    FCounterLock.Release;
  end;
  If inherited TryEnter then begin
    FCurrentThread := TThread.CurrentThread.ThreadID;
    FStartedTimestamp := GetTickCount;
    Result := true;
  end else Result := false;
  FCounterLock.Acquire;
  try
    FWaitingForCounter := FWaitingForCounter - 1;
  finally
    FCounterLock.Release;
  end;
end;

initialization
  _threads := TPCThreadList.Create('GLOBAL_THREADS');
finalization
  {$IFnDEF FPC}
  FreeAndNil(_threads);
  {$ENDIF}
end.

