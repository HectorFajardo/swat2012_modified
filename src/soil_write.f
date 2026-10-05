      subroutine soil_write

!!    ~ ~ ~ PURPOSE ~ ~ ~
!!    this subroutine writes daily soil P pool output to output.snu
!!    (unit 121, opened in readfile.f when ISOL = 1).
!!    One line per HRU per soil layer per day with the six SWAT soil
!!    P pools (Neitsch et al., 2011, section 3:2, Fig. 3:2-2) of that
!!    layer in kg P/ha. Layers are NOT summed.

!!    ~ ~ ~ LOCAL DEFINITIONS ~ ~ ~
!!    name        |units         |definition
!!    ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
!!    lyr_p(6)    |kg P/ha       |P pools in soil layer l of HRU j
!!    pool order: 1 solution P          (sol_solp)       inorganic
!!                2 active mineral P    (sol_actp)       inorganic
!!                3 stable mineral P    (sol_stap)       inorganic
!!                4 fresh organic P     (sol_fop)        organic
!!                5 active humic org P  eq. 3:2.2.3      organic
!!                6 stable humic org P  eq. 3:2.2.4      organic
!!    xx          |kg N/ha       |active + stable humic organic N
!!    ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

!!    ~ ~ ~ ~ ~ ~ END SPECIFICATIONS ~ ~ ~ ~ ~ ~

      use parm

      integer :: j, l
      real*8 :: lyr_p(6), xx

      do j = 1,nhru
        do l = 1,sol_nly(j)
          !! P pools of layer l (read only, no state change)
          lyr_p(1) = sol_solp(l,j)
          lyr_p(2) = sol_actp(l,j)
          lyr_p(3) = sol_stap(l,j)
          lyr_p(4) = sol_fop(l,j)
          !! humic org P split with active/stable org N (eq 3:2.2.3-4)
          lyr_p(5) = 0.
          xx = sol_aorgn(l,j) + sol_orgn(l,j)
          if (cswat == 0 .and. xx > 1.e-6) then
            lyr_p(5) = sol_orgp(l,j) * sol_aorgn(l,j) / xx
          end if
          lyr_p(6) = sol_orgp(l,j) - lyr_p(5)

          write (121,1000) i, subnum(j), hruno(j), l, sol_z(l,j),
     &      lyr_p
        end do
      end do
      
      return
 1000 format ('SNU   ',i4,1x,a5,a4,i6,f10.1,6f12.4)
      end