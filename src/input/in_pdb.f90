MODULE in_pdb
!
!
!**********************************************************************************
!*  IN_PDB                                                                        *
!**********************************************************************************
!* This module reads a file in the Protein Data Bank (PDB) format.                *
!* The PDB format is officially described here:                                   *
!*     http://www.wwpdb.org/docs.html                                             *
!**********************************************************************************
!* (C) Oct. 2012 - Pierre Hirel                                                   *
!*     Unité Matériaux Et Transformations (UMET),                                 *
!*     Université de Lille 1, Bâtiment C6, F-59655 Villeneuve D'Ascq (FRANCE)     *
!*     pierre.hirel@univ-lille1.fr                                                *
!* Last modification: P. Hirel - 02 Feb. 2017                                     *
!**********************************************************************************
!* This program is free software: you can redistribute it and/or modify           *
!* it under the terms of the GNU General Public License as published by           *
!* the Free Software Foundation, either version 3 of the License, or              *
!* (at your option) any later version.                                            *
!*                                                                                *
!* This program is distributed in the hope that it will be useful,                *
!* but WITHOUT ANY WARRANTY; without even the implied warranty of                 *
!* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                  *
!* GNU General Public License for more details.                                   *
!*                                                                                *
!* You should have received a copy of the GNU General Public License              *
!* along with this program.  If not, see <http://www.gnu.org/licenses/>.          *
!**********************************************************************************
!
USE comv
USE constants
USE functions
USE messages
USE files
USE subroutines
!
IMPLICIT NONE
!
!
CONTAINS
!
SUBROUTINE READ_PDB(inputfile,H,P,comment,AUXNAMES,AUX)
!
CHARACTER(LEN=*),INTENT(IN):: inputfile
CHARACTER(LEN=1):: atom_altLoc, atom_chainID, atom_iCode
CHARACTER(LEN=2):: atom_element, atom_charge
CHARACTER(LEN=2):: species
CHARACTER(LEN=1):: atom_resName
CHARACTER(LEN=4):: atom_name
CHARACTER(LEN=128):: pdbline     !a bit longer than the size of a line
CHARACTER(LEN=128):: msg
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: AUXNAMES !names of auxiliary properties
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: comment
LOGICAL:: isreduced
INTEGER:: atom_serial, atom_resSeq
INTEGER:: i, j
INTEGER:: occupancy, q !index of properties in AUX
REAL(dp):: a, b, c, alpha, beta, gamma !supercell (conventional notation)
REAL(dp):: atom_occupancy, atom_tempFactor
REAL(dp):: P1, P2, P3
REAL(dp):: smass
REAL(dp),DIMENSION(3):: TN, UN
REAL(dp),DIMENSION(3,3):: H   !Base vectors of the supercell
REAL(dp),DIMENSION(3,3):: ORIGXN, SCALEN   !Origin and scale matrices
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: P
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: aentries
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: AUX !auxiliary properties
!
!
!Initialize variables
TN(:) = 0.d0
UN = 0.d0
ORIGXN(:,:) = 0.d0
SCALEN(:,:) = 0.d0
IF(ALLOCATED(aentries)) DEALLOCATE(aentries)
!
msg = 'entering READ_PDB'
CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
!
ALLOCATE(AUXNAMES(2))
occupancy=1
q=2
AUXNAMES(occupancy) = "occupancy"
AUXNAMES(q) = "q"
!
!
!
100 CONTINUE
OPEN(UNIT=30,FILE=inputfile,STATUS='UNKNOWN',ERR=800)
!
!Parse the file a first time to know how many atoms and how many lines of comment it contains
i=0
j=0
DO
  READ(30,'(a128)',ERR=110,END=110) pdbline
  pdbline = ADJUSTL(pdbline)
  IF( pdbline(1:6)=='ATOM  ' .OR. pdbline(1:6)=='HETATM' ) THEN
    i=i+1
  ELSEIF( pdbline(1:6)=='HEADER' .OR. pdbline(1:6)=='TITLE ' .OR. pdbline(1:6)=='COMPND' .OR. pdbline(1:6)=='SOURCE' .OR. &
        & pdbline(1:6)=='KEYWDS' .OR. pdbline(1:6)=='EXPDTA' .OR. pdbline(1:6)=='AUTHOR' .OR. pdbline(1:6)=='REVDAT' .OR. &
        & pdbline(1:6)=='JRNL  ' .OR. pdbline(1:6)=='REMARK' .OR. pdbline(1:6)=='SEQRES') THEN
    j=j+1
  ENDIF
ENDDO
!
110 CONTINUE
WRITE(msg,*) 'NP = ', i
CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
WRITE(msg,*) 'comment lines: ', j
CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
!If no atom was found in the file we are in trouble
IF( i==0 ) THEN
  nerr = nerr+1
  GOTO 1000
ELSE
  ALLOCATE(P(i,4))
  P(:,:) = 0.d0
  ALLOCATE( AUX(i,SIZE(AUXNAMES)) )
  AUX(:,:) = 0.d0
  AUX(:,occupancy) = 1.d0  !default all occupancies to 1 in case they are missing in the file
ENDIF
IF(j>0) THEN
  ALLOCATE(comment(j))
  comment(:) = ''
ENDIF
!
!Go back to beginning of file and store data
REWIND(30)
i=0
j=0
DO
  READ(30,'(a128)',ERR=200,END=200) pdbline
  pdbline = ADJUSTL(pdbline)
  IF( pdbline(1:6)=='HEADER' .OR. pdbline(1:6)=='TITLE ' .OR. pdbline(1:6)=='COMPND' .OR. pdbline(1:6)=='SOURCE' .OR. &
    & pdbline(1:6)=='KEYWDS' .OR. pdbline(1:6)=='EXPDTA' .OR. pdbline(1:6)=='AUTHOR' .OR. pdbline(1:6)=='REVDAT' .OR. &
    & pdbline(1:6)=='JRNL  ' .OR. pdbline(1:6)=='REMARK' .OR. pdbline(1:6)=='SEQRES') THEN
    !Save this line as comment
    j=j+1
    comment(j) = pdbline
    !
  ELSEIF( pdbline(1:6)=='CRYST1' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) a, b, c, alpha, beta, gamma
    alpha = DEG2RAD(alpha)
    beta = DEG2RAD(beta)
    gamma = DEG2RAD(gamma)
    CALL CONVMAT(a,b,c,alpha,beta,gamma,H)
    !
  ELSEIF( pdbline(1:6)=='SCALE1' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) SCALEN(1,1), SCALEN(1,2), SCALEN(1,3), UN(1)
  ELSEIF( pdbline(1:6)=='SCALE2' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) SCALEN(2,1), SCALEN(2,2), SCALEN(2,3), UN(1)
  ELSEIF( pdbline(1:6)=='SCALE3' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) SCALEN(3,1), SCALEN(3,2), SCALEN(3,3), UN(1)
    !
  ELSEIF( pdbline(1:6)=='ORIGX1' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) ORIGXN(1,1), ORIGXN(1,2), ORIGXN(1,3), TN(1)
  ELSEIF( pdbline(1:6)=='ORIGX2' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) ORIGXN(2,1), ORIGXN(2,2), ORIGXN(2,3), TN(2)
  ELSEIF( pdbline(1:6)=='ORIGX3' ) THEN
    !Cell parameters
    READ(pdbline(7:80),*,ERR=801,END=801) ORIGXN(3,1), ORIGXN(3,2), ORIGXN(3,3), TN(3)
    !
  ELSEIF( pdbline(1:6)=='ATOM  ' .OR. pdbline(1:6)=='HETATM' ) THEN
    !This line contains information about an atom: read it
    !
    !Set atom index
    !Note: the "atom index" appearing in columns 7:11 cannot be used as actual index here,
    !     because termination lines (starting with TER) also have an index.
    !     As a result we just use a counter here.
    i=i+1
    IF(i>SIZE(P,1)) GOTO 800
    !
    !Read auxiliary properties?
    !READ(pdbline(13:16),*,ERR=801,END=801) atom_name
    !READ(pdbline(17:17),*,ERR=801,END=801) atom_altLoc
    !READ(pdbline(18:20),*,ERR=801,END=801) atom_resname
    !READ(pdbline(22:22),*,ERR=801,END=801) atom_chainID
    !READ(pdbline(23:26),*,ERR=801,END=801) atom_resSeq
    !READ(pdbline(27:27),*,ERR=801,END=801) atom_iCode
    !
    !Read atom position
    READ(pdbline(31:38),*,ERR=801,END=801) P1
    READ(pdbline(39:46),*,ERR=801,END=801) P2
    READ(pdbline(47:54),*,ERR=801,END=801) P3
    !
    IF( VECLENGTH(ORIGXN(1,:))>1.d-8 .AND.  &
      & VECLENGTH(ORIGXN(2,:))>1.d-8 .AND.  &
      & VECLENGTH(ORIGXN(3,:))>1.d-8        ) THEN
      !Transform atom coordinates
      P(i,1) = P1*ORIGXN(1,1) + P2*ORIGXN(1,2) + P3*ORIGXN(1,3) + TN(1)
      P(i,2) = P1*ORIGXN(2,1) + P2*ORIGXN(2,2) + P3*ORIGXN(2,3) + TN(2)
      P(i,3) = P1*ORIGXN(3,1) + P2*ORIGXN(3,2) + P3*ORIGXN(3,3) + TN(3)
    ELSE
      !Coordinates must be Cartesian => save them as-is
      P(i,1) = P1
      P(i,2) = P2
      P(i,3) = P3
    ENDIF
    !
    !Read atom occupancy. This may be missing
    IF( LEN_TRIM(pdbline(55:60))>0 ) THEN
      READ(pdbline(55:60),*,ERR=150,END=150) AUX(i,occupancy)
    ENDIF
    150 CONTINUE
    !
    !READ(pdbline(61:66),*,ERR=801,END=801) atom_tempFactor
    !
    !Read atom species
    READ(pdbline(77:78),*,ERR=801,END=801) species
    !In PDB atom species is in capital letters, e.g. "AL" for aluminum, "CU" for copper, etc.
    !Make sure to convert that to standard letter case, e.g. "Al", "Cu", etc.
    species(1:1) = StrUpCase(species(1:1))
    species(2:2) = StrDnCase(species(2:2))
    CALL ATOMNUMBER(ADJUSTL(species),P(i,4))
    !
    !Read atom charge. This may be missing
    IF( LEN_TRIM(pdbline(79:79))>0 ) THEN
      READ(pdbline(79:79),*,ERR=160,END=160) AUX(i,q)
      IF( pdbline(80:80)=="-" ) THEN
        AUX(i,q) = -1.d0*AUX(i,q)
      ENDIF
    ENDIF
    160 CONTINUE
    !
  ELSEIF( pdbline(1:4)=='END ' ) THEN
    !End of structure or PDB file: exit loop
    EXIT
  ENDIF
ENDDO
!
!
!
200 CONTINUE
CLOSE(30)
!If all cell vectors are set to 1, it means they are not set => set them to zero
IF( DABS(VECLENGTH(H(1,:)))-1.d0<1.d-12 .AND.         &
  & DABS(VECLENGTH(H(2,:)))-1.d0<1.d-12 .AND.         &
  & DABS(VECLENGTH(H(3,:)))-1.d0<1.d-12      ) THEN
  H(:,:) = 0.d0
ENDIF
GOTO 1000
!
!
!
800 CONTINUE
801 CONTINUE
CALL ATOMSK_MSG(802,(/''/),(/DBLE(i)/))
nerr = nerr+1
!
!
!
1000 CONTINUE
!
!
END SUBROUTINE READ_PDB
!
END MODULE in_pdb
