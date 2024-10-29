program FlushFileCache;

{$APPTYPE CONSOLE}

{$SetPEFlags $0001}

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
   Winapi.Windows;

type
   SYSTEM_INFORMATION_CLASS = (
      SystemFileCacheInformation = 21,
      SystemMemoryListInformation = 80
   );

   SYSTEM_FILECACHE_INFORMATION = record
      CurrentSize : NativeUInt;
      PeakSize : NativeUInt;
      PageFaultCount : ULONG;
      MinimumWorkingSet : NativeInt;
      MaximumWorkingSet : NativeInt;
      CurrentSizeIncludingTransitionInPages : NativeUInt;
      PeakSizeIncludingTransitionInPages : NativeUInt;
      TransitionRePurposeCount : ULONG;
      Flags : ULONG;
   end;
   PSYSTEM_FILECACHE_INFORMATION = ^SYSTEM_FILECACHE_INFORMATION;

   SYSTEM_MEMORY_LIST_COMMAND = (
      MemoryCaptureAccessedBits,
      MemoryCaptureAndResetAccessedBits,
      MemoryEmptyWorkingSets,
      MemoryFlushModifiedList,
      MemoryPurgeStandbyList,
      MemoryPurgeLowPriorityStandbyList,
      MemoryCommandMax
   );

var
   NtSetSystemInformation : function  (
      SystemInformationClass: SYSTEM_INFORMATION_CLASS;
      SystemInformation: Pointer; //  __in_bcount_opt(SystemInformationLength) PVOID SystemInformation,
      SystemInformationLength: ULONG) : Integer; stdcall;

function SendMemoryCommand(command : SYSTEM_MEMORY_LIST_COMMAND) : Integer;
var
   buf : Integer;
begin
   buf:=Integer(command);
   Result:=NtSetSystemInformation(SystemMemoryListInformation, @buf, SizeOf(buf))
end;

function SetPrivilege(hToken : THandle; lpszPrivilege : PWideChar; bEnablePrivilege : Boolean) : Boolean;
var
   tp : TTokenPrivileges;
   luid : Int64;
   rl : DWORD;
begin
   if (not LookupPrivilegeValue(nil, lpszPrivilege, luid)) then
      Exit(False);

   tp.PrivilegeCount := 1;
   tp.Privileges[0].Luid := luid;
   if bEnablePrivilege then
      tp.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED
   else tp.Privileges[0].Attributes := 0;

   if (not AdjustTokenPrivileges(hToken, FALSE, tp, sizeof(TOKEN_PRIVILEGES), nil, rl)) then
      Exit(False);

   Result := (GetLastError() <> ERROR_NOT_ALL_ASSIGNED);
end;

var
   ntdll : HMODULE;
   processToken : THandle;
   info : SYSTEM_FILECACHE_INFORMATION;
   command : Integer;
   option : String;
   full : Boolean;
begin
   WriteLn('FlushFileCache v1.0 - www.DelphiTools.info'#13#10);

   case ParamCount of
      0 : option:='';
      1 : option:=ParamStr(1);
   else
      option:='help';
   end;

   full:=False;
   if option<>'' then begin
      if option='full' then
         full:=True
      else begin
         Writeln('  help    Show this help');
         Writeln('  full    Flush everything (slow)');
      end;
   end;

   // Get NtSetSystemInformation
   ntdll := LoadLibrary('NTDLL.DLL');
   NtSetSystemInformation := GetProcAddress(ntdll, 'NtSetSystemInformation');
   if not Assigned(NtSetSystemInformation) then begin
      Writeln('Unsupported OS version');
      Exit;
   end;

   if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, processToken) = FALSE) then begin
      Writeln('Failed to open privileges token');
      Exit;
   end;

   // Clear FileCache WorkingSet

   if SetPrivilege(processToken, 'SeIncreaseQuotaPrivilege', True) then begin

      ZeroMemory(@info, sizeof(info));
      info.MinimumWorkingSet := -1;
      info.MaximumWorkingSet := -1;
      if NtSetSystemInformation(SystemFileCacheInformation, @info, sizeof(info))>=0 then
         Writeln('Flushed FileCache WorkingSet')
      else Writeln('Failed to flush FileCache WorkingSet');

   end else Writeln('Failed to obtain IncreaseQuotaPrivilege');

   // Purge Memory Standby

   if SetPrivilege(processToken, 'SeProfileSingleProcessPrivilege', True) then begin

      command := Integer(MemoryEmptyWorkingSets);
      if NtSetSystemInformation(SystemMemoryListInformation, @command, sizeof(command))>=0 then
         Writeln('Emptied Memory Working Sets')
      else Writeln('Failed to empty Memory Working Sets');

      if full then begin
         if SendMemoryCommand(MemoryFlushModifiedList)>=0 then
            Writeln('Flush Modified List')
         else Writeln('Failed to flush Modified List');

         if SendMemoryCommand(MemoryPurgeStandbyList)>=0 then
            Writeln('Purged Memory Standby List')
         else Writeln('Failed to purge Memory Standby List');

         if SendMemoryCommand(MemoryPurgeLowPriorityStandbyList)>=0 then
            Writeln('Purged Memory Low-Priority Standby List')
         else Writeln('Failed to purge Memory Low-Priority Standby List');
      end;

   end else Writeln('Failed to obtain ProfileSingleProcessPrivilege');
end.
