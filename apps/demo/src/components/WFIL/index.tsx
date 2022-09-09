import { useCallback, useMemo } from 'react'
import styled from 'styled-components'
import { useAccount, useSigner } from 'wagmi'
import { WFIL__factory } from '../../../typechain'
import { useWFILBalance } from '../../utils'
import { Deposit } from './Deposit'
import contractDigest from '../../../generated/contractDigest.json'
import { GrantAllowance } from './GrantAllowance'
import Layout from '../Layout'
const { WFIL: WFILContract } = contractDigest

const Container = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
`

export function WFIL() {
  const { address } = useAccount()
  const { balance: wFILBalance } = useWFILBalance(address)

  const { data: signer } = useSigner()
  const contract = useMemo(() => {
    return WFIL__factory.connect(WFILContract.address, signer)
  }, [signer])

  const onDeposit = useCallback(
    async (amount) => {
      contract.deposit({ value: amount.toAttoFil() })
    },
    [contract]
  )

  const onGrantAllowance = useCallback(
    async (spender, amount) => {
      contract.approve(spender, amount.toAttoFil())
    },
    [contract]
  )

  return (
    <Layout>
      <Container>
        <Deposit onSubmit={onDeposit} wFILBalance={wFILBalance} />
        <GrantAllowance onSubmit={onGrantAllowance} wFILBalance={wFILBalance} />
      </Container>
    </Layout>
  )
}
