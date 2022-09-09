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

export function Deposit(props: DepositProps) {
  const [amount, setAmount] = useState(new FilecoinNumber('0', 'fil'))
  return (
    <Dialog>
      <form
        onSubmit={async (e) => {
          e.preventDefault()
          props.onSubmit(amount)
        }}
      >
        <StandardBox>
          <h2>Get WFIL</h2>
          <hr />
          <p>Exchange FIL for WFIL below</p>
        </StandardBox>
        <ShadowBox>
          <Lines>
            <Line label='WFIL Balance'>{props.wFILBalance.toFil()} FIL</Line>
          </Lines>
          <br />
          <InputV2.Filecoin
            value={amount}
            onChange={setAmount}
            label='Amount'
          />
        </ShadowBox>
        <ButtonV2 type='submit' green>
          Get WFIL
        </ButtonV2>
      </form>
    </Dialog>
  )
}

type DepositProps = {
  onSubmit: (amount: FilecoinNumber) => Promise<void>
  wFILBalance: FilecoinNumber
}
