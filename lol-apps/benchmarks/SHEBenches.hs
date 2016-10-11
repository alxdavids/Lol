{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module SHEBenches (sheBenches, decBenches, rescaleBenches, tunnelBenches) where

import Crypto.Lol.Benchmarks

import Control.Applicative
import Control.Monad.Random
import Control.Monad.State
import Crypto.Random.DRBG

import Crypto.Lol
import Crypto.Lol.Applications.SymmSHE
import Crypto.Lol.Types hiding (CT)
import Crypto.Lol.Types.ZPP

addGen5 :: Proxy gen -> Proxy '(t,m,m',zp,zq) -> Proxy '(t,m,m',zp,zq,gen)
addGen5 _ _ = Proxy

addGen6 :: Proxy gad -> Proxy '(t,m,m',zp,zq,zq') -> Proxy '(t,m,m',zp,zq,zq',gad)
addGen6 _ _ = Proxy

sheBenches :: forall t m m' zp zq gen rnd . (MonadRandom rnd, _)
  => Proxy '(m,m',zp,zq) -> Proxy gen -> Proxy t -> [rnd Benchmark]
sheBenches _ pgen _ =
  let ptmr = Proxy :: Proxy '(t,m,m',zp,zq)
  in ($ ptmr) <$> [
    genBenchArgs "encrypt"   bench_enc . addGen5 pgen,
    genBenchArgs "*"         bench_mul,
    genBenchArgs "addPublic" bench_addPublic,
    genBenchArgs "mulPublic" bench_mulPublic
    ]

-- zq must be Liftable
decBenches :: forall t m m' zp zq rnd . (MonadRandom rnd, _)
  => Proxy '(m,m',zp,zq) -> Proxy t -> [rnd Benchmark]
decBenches _ _ =
  let ptmr = Proxy::Proxy '(t,m,m',zp,zq)
  in [genBenchArgs "decrypt" bench_dec ptmr]

-- must be able to round from zq' to zq
rescaleBenches :: forall t m m' zp zq zq' gad rnd . (MonadRandom rnd, _)
  => Proxy '(m,m',zp,zq,zq') -> Proxy gad -> Proxy t -> [rnd Benchmark]
rescaleBenches _ pgad _ =
  let ptmr = Proxy :: Proxy '(t,m,m',zp,zq,zq')
  in ($ ptmr) <$> [genBenchArgs "rescaleCT" bench_rescaleCT,
                   genBenchArgs "keySwitch" bench_keySwQ . addGen6 pgad]

tunnelBenches :: forall t r r' s s' zp zq gad rnd . (MonadRandom rnd, _)
  => Proxy '(r,r',s,s',zp,zq) -> Proxy gad -> Proxy t -> [rnd Benchmark]
tunnelBenches _ _ _ =
  let ptmr = Proxy :: Proxy '(t,r,r',s,s',zp,zq,gad)
  in [genBenchArgs "tunnel" bench_tunnel ptmr]


bench_enc :: forall t m m' z zp (zq :: *) (gen :: *) . (z ~ LiftOf zp,  _)
  => SK (Cyc t m' z) -> PT (Cyc t m zp) -> Bench '(t,m,m',zp,zq,gen)
bench_enc sk pt = benchIO $ do
  gen <- newGenIO
  return $ evalRand (encrypt sk pt :: Rand (CryptoRand gen) (CT m zp (Cyc t m' zq))) gen

-- requires zq to be Liftable
bench_dec :: forall t m m' z zp zq . (z ~ LiftOf zp, _)
  => PT (Cyc t m zp) -> SK (Cyc t m' z) -> Bench '(t,m,m',zp,zq)
bench_dec pt sk = benchM $ do
  ct :: CT m zp (Cyc t m' zq) <- encrypt sk pt
  return $ bench (decrypt sk) ct

bench_mul :: forall t m m' z zp zq . (z ~ LiftOf zp, LiftOf zp ~ ModRep zp, _)
  => PT (Cyc t m zp) -> PT (Cyc t m zp) -> SK (Cyc t m' z) -> (Bench '(t,m,m',zp,zq))
bench_mul pta ptb sk = benchM $ do
  a :: CT m zp (Cyc t m' zq) <- encrypt sk pta
  b <- encrypt sk ptb
  return $ bench (*a) b

bench_addPublic :: forall t m m' z zp zq . (z ~ LiftOf zq, _)
  => Cyc t m zp -> PT (Cyc t m zp) -> SK (Cyc t m' z) -> Bench '(t,m,m',zp,zq)
bench_addPublic a pt sk = benchM $ do
  ct :: CT m zp (Cyc t m' zq) <- encrypt sk pt
  return $ bench (addPublic a) ct

bench_mulPublic :: forall t m m' z zp zq . (z ~ LiftOf zq, _)
  => Cyc t m zp -> PT (Cyc t m zp) -> SK (Cyc t m' z) -> Bench '(t,m,m',zp,zq)
bench_mulPublic a pt sk = benchM $ do
  ct :: CT m zp (Cyc t m' zq) <- encrypt sk pt
  return $ bench (mulPublic a) ct

bench_rescaleCT :: forall t m m' z zp (zq :: *) (zq' :: *) . (z ~ LiftOf zq, _)
  => PT (Cyc t m zp) -> SK (Cyc t m' z) -> Bench '(t,m,m',zp,zq,zq')
bench_rescaleCT pt sk = benchM $ do
  ct <- encrypt sk pt
  return $ bench (rescaleLinearCT :: CT m zp (Cyc t m' zq') -> CT m zp (Cyc t m' zq)) ct

bench_keySwQ :: forall t m m' z zp zq (zq' :: *) (gad :: *) . (z ~ LiftOf zp, _)
  => PT (Cyc t m zp) -> SK (Cyc t m' z) -> Bench '(t,m,m',zp,zq,zq',gad)
bench_keySwQ pt sk = benchM $ do
  x :: CT m zp (Cyc t m' zq) <- encrypt sk pt
  kswq <- proxyT (keySwitchQuadCirc sk) (Proxy::Proxy (gad,zq'))
  let y = x*x
  return $ bench kswq y

-- possible bug: If I enable -XPartialTypeSigs and add a ",_" to the constraint list below, GHC
-- can't figure out that `e `Divides` s`, even when it's explicitly listed!
bench_tunnel :: forall t e e' r r' s s' z zp zq gad .
  (z ~ LiftOf zp,
   TunnelCtx t e r s e' r' s' z zp zq gad,
   e ~ FGCD r s,
   ZPP zp, Mod zp,
   z ~ ModRep zp,
   r `Divides` r',
   Fact e,
   NFData zp,
   CElt t (ZpOf zp))
  => PT (Cyc t r zp) -> SK (Cyc t r' z) -> SK (Cyc t s' z) -> Bench '(t,r,r',s,s',zp,zq,gad)
bench_tunnel pt skin skout = benchM $ do
  x :: CT r zp (Cyc t r' zq) <- encrypt skin pt
  let crts :: [Cyc t s zp] = proxy crtSet (Proxy::Proxy e) \\ gcdDivides (Proxy::Proxy r) (Proxy::Proxy s)
      r = proxy totientFact (Proxy::Proxy r)
      e = proxy totientFact (Proxy::Proxy e)
      dim = r `div` e
      -- only take as many crts as we need
      -- otherwise linearDec fails
      linf :: Linear t zp e r s = linearDec (take dim crts) \\ gcdDivides (Proxy::Proxy r) (Proxy::Proxy s)
  hints <- proxyT (tunnelCT linf skout skin) (Proxy::Proxy gad)
  return $ bench hints x


-- generates a secret key with scaled variance 1.0
instance (GenSKCtx t m' z Double) => Random (SK (Cyc t m' z)) where
  random = runRand $ genSK (1 :: Double)
  randomR = error "randomR not defined for SK"


{-
-- 3144961,5241601,7338241,9959041,10483201,11531521,12579841,15200641,18869761,19393921
type TunnParams =
  ( '(,) <$> Gadgets) <*>
  (( '(,) <$> Tensors) <*>
  (( '(,) <$> TunnRings) <*> TunnMods))
tunnelParams :: Proxy TunnParams
tunnelParams = Proxy

type TunnRings = '[
  {- H0 -> H1 -} '(F128, F128 * F7 * F13, F64 * F7, F64 * F7 * F13),
  {- H1 -> H2 -} '(F64 * F7, F64 * F7 * F13, F32 * F7 * F13, F32 * F7 * F13),
  {- H2 -> H3 -} '(F32 * F7 * F13, F32 * F7 * F13, F8 * F5 * F7 * F13, F8 * F5 * F7 *F13),
  {- H3 -> H4 -} '(F8 * F5 * F7 * F13, F8 * F5 * F7 *F13, F4 * F3 * F5 * F7 * F13, F4 * F3 * F5 * F7 * F13),
  {- H4 -> H5 -} '(F4 * F3 * F5 * F7 * F13, F4 * F3 * F5 * F7 *F13, F9 * F5 * F7 * F13, F9 * F5 * F7 * F13)
    ]

type TunnMods = '[
  '(Zq PP32, Zq 3144961)
  ]
-}