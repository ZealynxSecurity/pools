import { FilecoinNumber } from '@glif/filecoin-number'
import {
  ButtonV2,
  Dialog,
  InputV2,
  Line,
  Lines,
  ShadowBox,
  StandardBox
} from '@glif/react-components'
import { useState } from 'react'

export function GrantAllowance(props: GrantAllowanceProps) {
  const [amount, setAmount] = useState(new FilecoinNumber('0', 'fil'))
  const [spender, setSpender] = useState('')

  return (
    <Dialog>
      <form
        onSubmit={async (e) => {
          e.preventDefault()
          props.onSubmit(spender, amount)
        }}
      >
        <StandardBox>
          <h2>Approve an address to spend your WFIL</h2>
          <hr />
          <p>Enter an address and an amount below to grant an allowance</p>
        </StandardBox>
        <ShadowBox>
          <Lines>
            <Line label='WFIL Balance'>{props.wFILBalance.toFil()} FIL</Line>
          </Lines>
          <br />
          <InputV2.Filecoin
            value={amount}
            onChange={setAmount}
            label='Amount to approve'
          />
          <br />
          <InputV2.Text value={spender} onChange={setSpender} label='Spender' />
        </ShadowBox>
        <ButtonV2 type='submit' green>
          Grant approval
        </ButtonV2>
      </form>
    </Dialog>
  )
}

type GrantAllowanceProps = {
  onSubmit: (spender: string, amount: FilecoinNumber) => Promise<void>
  wFILBalance: FilecoinNumber
}
