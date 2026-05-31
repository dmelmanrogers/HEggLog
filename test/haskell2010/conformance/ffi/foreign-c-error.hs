module Main where

import Foreign.C.Error
import Foreign.C.Error (Errno(Errno))
import Foreign.C.Types (CInt)
import System.IO.Error (catch, ioeGetErrorString, ioeGetFileName)

foreign import ccall "hegglog_ffi_set_errno_minus1" c_fail :: CInt -> IO CInt
foreign import ccall "hegglog_ffi_reset_retry_count" c_reset_retry :: IO ()
foreign import ccall "hegglog_ffi_retry_after_eintr" c_retry_after_eintr :: IO CInt
foreign import ccall "hegglog_ffi_retry_after_eagain" c_retry_after_eagain :: IO CInt

isMinusOne :: CInt -> Bool
isMinusOne value = value == (0 - 1)

errnoSamples :: [CInt]
errnoSamples = [eOK, e2BIG, eACCES, eADDRINUSE, eADDRNOTAVAIL, eADV, eAFNOSUPPORT, eAGAIN, eALREADY, eBADF, eBADMSG, eBADRPC, eBUSY, eCHILD, eCOMM, eCONNABORTED, eCONNREFUSED, eCONNRESET, eDEADLK, eDESTADDRREQ, eDIRTY, eDOM, eDQUOT, eEXIST, eFAULT, eFBIG, eFTYPE, eHOSTDOWN, eHOSTUNREACH, eIDRM, eILSEQ, eINPROGRESS, eINTR, eINVAL, eIO, eISCONN, eISDIR, eLOOP, eMFILE, eMLINK, eMSGSIZE, eMULTIHOP, eNAMETOOLONG, eNETDOWN, eNETRESET, eNETUNREACH, eNFILE, eNOBUFS, eNODATA, eNODEV, eNOENT, eNOEXEC, eNOLCK, eNOLINK, eNOMEM, eNOMSG, eNONET, eNOPROTOOPT, eNOSPC, eNOSR, eNOSTR, eNOSYS, eNOTBLK, eNOTCONN, eNOTDIR, eNOTEMPTY, eNOTSOCK, eNOTTY, eNXIO, eOPNOTSUPP, ePERM, ePFNOSUPPORT, ePIPE, ePROCLIM, ePROCUNAVAIL, ePROGMISMATCH, ePROGUNAVAIL, ePROTO, ePROTONOSUPPORT, ePROTOTYPE, eRANGE, eREMCHG, eREMOTE, eROFS, eRPCMISMATCH, eRREMOTE, eSHUTDOWN, eSOCKTNOSUPPORT, eSPIPE, eSRCH, eSRMNT, eSTALE, eTIME, eTIMEDOUT, eTOOMANYREFS, eTXTBSY, eUSERS, eWOULDBLOCK, eXDEV]

errorPath :: IOError -> String
errorPath err =
  case ioeGetFileName err of
    Just path -> path
    Nothing -> "missing"

main :: IO ()
main = do
  resetErrno
  initial <- getErrno
  print initial

  ok <- throwErrnoIfMinus1 "ok" (return (5 :: CInt))
  print ok

  message <- catch (throwErrnoIfMinus1 "denied" (c_fail eACCES) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn message

  unitMessage <- catch (throwErrnoIfMinus1_ "denied-unit" (c_fail eACCES) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn unitMessage

  print eINTR
  print (isValidErrno eACCES)
  print (isValidErrno (Errno (0 - 1)))
  print (length errnoSamples)
  print (isValidErrno (Errno 0))

  c_reset_retry
  genericRetry <- throwErrnoIfRetry isMinusOne "generic-retry" c_retry_after_eintr
  print genericRetry

  c_reset_retry
  throwErrnoIfRetry_ isMinusOne "generic-retry-unit" c_retry_after_eintr
  putStrLn "generic-unit-ok"

  c_reset_retry
  minusRetry <- throwErrnoIfMinus1Retry "minus-retry" c_retry_after_eintr
  print minusRetry

  c_reset_retry
  throwErrnoIfMinus1Retry_ "minus-retry-unit" c_retry_after_eintr
  putStrLn "minus-unit-ok"

  c_reset_retry
  mayBlock <- throwErrnoIfRetryMayBlock isMinusOne "mayblock" c_retry_after_eagain (putStrLn "blocked")
  print mayBlock

  c_reset_retry
  throwErrnoIfRetryMayBlock_ isMinusOne "mayblock-unit" c_retry_after_eagain (putStrLn "blocked-unit")
  putStrLn "mayblock-unit-ok"

  c_reset_retry
  minusMayBlock <- throwErrnoIfMinus1RetryMayBlock "minus-mayblock" c_retry_after_eagain (putStrLn "minus-blocked")
  print minusMayBlock

  c_reset_retry
  throwErrnoIfMinus1RetryMayBlock_ "minus-mayblock-unit" c_retry_after_eagain (putStrLn "minus-blocked-unit")
  putStrLn "minus-mayblock-unit-ok"

  pathMessage <- catch (throwErrnoPathIfMinus1 "path-denied" "secret.txt" (c_fail eACCES) >> return "bad") (\err -> return (errorPath err))
  putStrLn pathMessage

  pathUnitMessage <- catch (throwErrnoPathIfMinus1_ "path-denied-unit" "unit-secret.txt" (c_fail eACCES) >> return "bad") (\err -> return (errorPath err))
  putStrLn pathUnitMessage
