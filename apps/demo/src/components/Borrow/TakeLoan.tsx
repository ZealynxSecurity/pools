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
import { useSigner } from 'wagmi'

import { usePool, usePools } from '../../utils'
import { SimpleInterestPool__factory } from '../../../typechain'
import contractDigest from '../../../generated/contractDigest.json'

const { LoanAgent } = contractDigest

export function TakeLoan() {
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
  const { data: signer } = useSigner()

  const onSubmit = useCallback(
    async (e: FormEvent<HTMLFormElement>) => {
      e.preventDefault()
      const p = SimpleInterestPool__factory.connect(pool.address, signer)
      const tx = await p.borrow(amount.toAttoFil(), LoanAgent[0].address)
      console.log(tx)
    },
    [pool.address, signer, amount]
  )

  return (
    <Dialog>
      <form onSubmit={onSubmit}>
        <StandardBox>
          <h2>Borrow from a pool</h2>
          <hr />
          <p>Select a loan pool to see its details and borrow from it</p>
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
            label='Borrow amount'
          />
          <br />
          {pool.id && (
            <Lines>
              <Line label='Interest rate'>
                {pool.interestRate.toFil()}% APR
              </Line>
              <Line label='Total assets'>{pool.totalAssets.toFil()} FIL</Line>
            </Lines>
          )}
        </ShadowBox>
        <ButtonV2 type='submit' green>
          Take loan
        </ButtonV2>
      </form>
    </Dialog>
  )
}
