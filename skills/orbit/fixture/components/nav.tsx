import Link from 'next/link'
import { NAV_LINKS } from '../lib/nav'

export function Nav() {
  return (
    <nav>
      {NAV_LINKS.map((l) => (
        <Link key={l.href} href={l.href}>
          {l.label}
        </Link>
      ))}
    </nav>
  )
}
