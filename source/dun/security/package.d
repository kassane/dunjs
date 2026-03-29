/// Security: Permission system.
///
/// Deno-inspired default-deny permission model.
/// Every I/O operation checks permissions before executing.
module dun.security;

public import dun.security.permissions;
