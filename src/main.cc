#include <common.h>
#include <constexpr.h>
#include <resolve.h>

using namespace stardust;

extern "C" auto declfn entry(
    _In_ void* args
) -> void {
    stardust::instance()
        .start( args );
}

declfn instance::instance(
    void
) {
    base.address = RipStart();
    base.length  = ( RipData() - base.address ) + END_OFFSET;

    if ( ! (( ntdll.handle = resolve::module( expr::hash_string<wchar_t>( L"ntdll.dll" ) ) )) ) {
        return;
    }

    if ( ! (( kernel32.handle = resolve::module( expr::hash_string<wchar_t>( L"kernel32.dll" ) ) )) ) {
        return;
    }

    RESOLVE_IMPORT( ntdll );
    RESOLVE_IMPORT( kernel32 );
}

auto declfn instance::start(
    _In_ void* arg
) -> void {
    kernel32.WinExec(
        symbol<const char*>( "C:\\Windows\\System32\\calc.exe" ),
        SW_SHOW
    );
}
