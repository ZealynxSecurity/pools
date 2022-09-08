import { FormEvent, useCallback, useMemo, useState } from 'react'
import {
  InputV2,
  Lines,
  Line,
  ShadowBox,
  Dialog,
  ButtonV2,
  StandardBox
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import { useAccount, useSigner } from 'wagmi'

import { useLoan, Loan, usePool, usePools } from '../../utils'
import { SimpleInterestPool__factory } from '../../../typechain'
import contractDigest from '../../../generated/contractDigest.json'

const { LoanAgent } = contractDigest

const getSIPrefix = (key: keyof Loan): 'toAttoFil' | 'toFil' => {
  switch (key) {
    case 'interest':
    case 'principal':
    case 'totalPaid':
      return 'toFil'
    default:
      return 'toAttoFil'
  }
}

export function Repay() {
  const [selectedPool, setSelectedPool] = useState('')
  const [amount, setAmount] = useState(new FilecoinNumber('0', 'fil'))
  // const [error, setError] = useState<string>('')
  const { pools, isLoading, error: usePoolsError } = usePools()

  const options = useMemo(() => {
    if (!isLoading && !usePoolsError && pools.length > 0) {
      return pools.map((p) => p.id)
    }
    return []
  }, [pools, isLoading, usePoolsError])

  const pool = usePool(selectedPool)
  const { address } = useAccount()
  const { data: signer } = useSigner()

  const {
    loan,
    balance: loanBalance,
    error: loanError
  } = useLoan(LoanAgent[0].address, pool.address)

  const onSubmit = useCallback(
    async (e: FormEvent<HTMLFormElement>) => {
      e.preventDefault()
      const p = SimpleInterestPool__factory.connect(pool.address, signer)
      const tx = await p.repay(
        amount.toAttoFil(),
        LoanAgent[0].address,
        address
      )
      console.log(tx)
    },
    [pool.address, signer, amount, address]
  )

  return (
    <Dialog>
      <form onSubmit={onSubmit}>
        <StandardBox>
          <h2>Repay a pool</h2>
          <hr />
          <p>Select a loan pool to repay</p>
        </StandardBox>
        <ShadowBox>
          <InputV2.Select
            label='Pool ID'
            options={options}
            value={selectedPool}
            onChange={setSelectedPool}
            // not working  ??? disabled={options.length === 0}
            placeholder='Select pool'
          />
          <br />
          <InputV2.Filecoin
            value={amount}
            onChange={setAmount}
            label='Repay amount'
          />
          <br />

          {!loanError && loan && (
            <Lines>
              <Line label='Owed today'>{loanBalance.bal.toFil()} FIL</Line>
              <Line label='Penalty'>{loanBalance.penalty.toFil()} FIL</Line>
              {Object.keys(loan).map((key: keyof Loan) => (
                <Line key={key} label={key}>
                  {loan[key][getSIPrefix(key)]()}
                </Line>
              ))}
              <Line label='Total owed'>
                {loan.interest.plus(loan.principal).toFil()} FIL
              </Line>
            </Lines>
          )}
        </ShadowBox>
        <ButtonV2 type='submit' green>
          Repay
        </ButtonV2>
      </form>
    </Dialog>
  )
}
