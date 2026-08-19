import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export const config = {
  matcher: ['/dash/:path*', '/settings/:path*'],
}

export function middleware(req: NextRequest) {
  const isAuthed = req.cookies.get('session')
  if (!isAuthed) {
    return NextResponse.redirect(new URL('/login', req.url))
  }
  return NextResponse.next()
}
