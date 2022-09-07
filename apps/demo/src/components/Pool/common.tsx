import { ShadowBox as _ShadowBox } from '@glif/react-components'
import styled from 'styled-components'

export enum DEPOSIT_ELIGIBILITY {
  LOADING,
  NEEDS_FIL,
  NEEDS_WFIL,
  NEEDS_WFIL_ALLOWANCE,
  READY
}

export const Form = styled.form`
  margin-left: 10%;
  margin-right: 10%;

  > button {
    width: 100%;
    margin-top: var(--space-m);
  }
`

export const ShadowBox = styled(_ShadowBox)`
  padding: 0;
  padding-bottom: 1.5em;

  > * {
    text-align: center;
  }
`

export const FormContainer = styled.div`
  margin-top: var(--space-l);
  display: flex;
  flex-direction: column;
  justify-content: center;

  > h3 {
    padding-left: var(--space-xl);
    padding-right: var(--space-xl);
  }

  > label {
    width: fit-content;
    margin-left: auto;
    margin-right: auto;
    margin-top: var(--space-l);
    margin-bottom: var(--space-l);
  }
`
