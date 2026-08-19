import Link from 'next/link'

export default function DashPage() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Link href="/dash/items">Items</Link>
    </div>
  )
}
