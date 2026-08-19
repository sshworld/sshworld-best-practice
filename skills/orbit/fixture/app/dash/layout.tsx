import { Nav } from '../../components/nav'

export default function DashLayout({ children }: { children: React.ReactNode }) {
  return (
    <div>
      <Nav />
      <main>{children}</main>
    </div>
  )
}
