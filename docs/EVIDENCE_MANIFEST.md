# Evidence Manifest

This manifest pins the private evidence set governing the K4L rebuild. The raw
`.deb`, IPA, executable images, decompiler output, decrypted corpora, and other
reverse-engineering artifacts are maintained outside this source repository.

The repository may contain clean-room source, independently written contracts,
and verified artifact hashes. It must not contain copied proprietary binaries or
decompiled application source.

## Authority and precedence

1. The Snapchat 14.15.0.48 evidence controls private Snapchat contracts for
   bundle `com.toyopagroup.picaboo`, version `14.15.0`, build `14.15.0.48`.
2. `Hush_Complete_Static_Mechanics_Report.md` controls recovered package
   mechanics.
3. Detailed ledgers and corpora support the primary reports.
4. Historical reports remain provenance only where superseded.
5. Final on-device observations may clarify runtime behavior, but may not
   silently replace static evidence.
6. No implementation claim may exceed its supporting evidence.

## Pinned artifact inventory

### Primary `.deb` mechanics manuals

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Hush_Complete_Static_Mechanics_Report.md` | 12,260 | `9cdb6b19d5b1f714b22bce2c0bea6afb1aa0779cee4d2a66807ed24dbf018b5e` |
| `Hush_Mechanics_Ledger.tsv` | 23,437 | `e416ea6cc51925dc9894f3034fc280fe9005de4145579fc56a0c3a32f172f5cc` |
| `Hush_Feature_Backend_Matrix.tsv` | 7,694 | `6a58240018dfbb173a189a91260f684aa9dd59da14b1cf70252eca35383d12d9` |
| `Hush_Resolved_SQL_Triggers.tsv` | 2,479 | `6084a94829974c37db8e086bc443f773ccb6fc3420117209dcd035d0a846963d` |
| `Hush_Hook_Map_Corrected.tsv` | 10,468 | `5d0171e560fb340230944e9c10a7aca3f13313680c48b2daea04cb9ce46e9127` |
| `Hush_15_Step_Evidence_Coverage.tsv` | 3,065 | `26f38a82610427b01df8ed8200004801e42e8efb98b0eb7a0a182ed1bf61fc61` |

### Decryption and package corpus

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Hush_All_Decrypted_Strings.tsv` | 166,891 | `312284eac5532ea2c694481f7305167d61b99bd6f15752f44a248becab2f2fb9` |
| `Hush_Encrypted_String_Coverage.md` | 2,614 | `13be0f6b61aebe283b32fa02f4c69c6289ace9f9ec867525ddc84f114588ecb5` |
| `Hush_SQL_Corpus.tsv` | 15,417 | `7c96d837d89bf76f773f14883413f4dc04ff764db4dcfc659d6bbe93627864a2` |
| `Hush_PATH_Corpus.tsv` | 11,819 | `5b78480aae36d96062b9b6915b93feb08f51cb9e3ecf6a7d3f511d0d4adc26da` |
| `Hush_COMMAND_Corpus.tsv` | 740 | `8167c246a4adc0c387335a2d7f7eaa0d7a5194f52ae29fade0fdeaab7bb90d7a` |
| `Hush_NOTIFY_Corpus.tsv` | 1,360 | `d70c11fb4e9529572aa588704b1270749045b80ba945c0fe9ec0fbad14cc7d04` |
| `Hush_Package_File_Inventory.tsv` | 5,962 | `dacf26783d8d60de69c07a59b841848d01bb86cf7ef041aaec69ad291b3c4a07` |
| `Hush_Reverse_Artifact_Index.md` | 3,407 | `5929bf91f36ae12c4580cad4a49ee69ea24527c01e1e811e4e6a06935290cf1d` |

### Snapchat 14.15.0.48 manuals

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Snapchat_14_15_0_48_IPA_Resolution_Report.md` | 6,287 | `1450a3c085b12cb1a57ee531d0566ab4ebb51aef2ccb9cef78b2a1cdfd23cf21` |
| `Snapchat_14_15_0_48_Private_API_Map.tsv` | 6,392 | `29dcc1f94b1601716a12f881915ea4aa9ef9f83e2164df61d9c9a4932776d30c` |
| `Snapchat_14_15_0_48_Resolved_Unknowns.tsv` | 2,452 | `48766ec959efac4f56b02c02113a985623c2260c7e4f2533bee933d5e55b9144` |
| `Hush_Resolved_SQL_Triggers_With_Snapchat_14_15_0_48.tsv` | 1,931 | `a929da79e5c372690bbba970750e980137ceebfd54d1d40b3b71860b0896e93c` |

### Historical supporting reports

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Hush_DEB_Deep_Dive_Step11_Report.md` | 20,574 | `d8f8be4894f824d44278044baf785a4af4b18c697c99c53e79b14fbb3a17b014` |
| `Hush_DEB_Deeper_Reverse_Step11_Report.md` | 33,897 | `05dc20fdf55d87a479ce2c7a678882025f320f0ade92fc39cd48d9f915e11873` |
| `Hush_DEB_Final_Unsolved_Resolution_Report.md` | 21,174 | `9cdb5c4bc3715cfe706f7088ff6451ef3cce5112281b41650e814d13aff9dcc5` |

### External binary evidence

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `com.toyopagroup.picaboo_14.15.0_decrypted(1).ipa` | 154,762,205 | `8c2a4aa8afd217cd6491518544a3179f0001905a5949fff277c5e08701e40af2` |

## Required classifications

Every mechanic derived from this evidence must use one evidence classification:

- `PROVEN`
- `IMPLEMENTATION-EQUIVALENT`
- `FINAL DEVICE CONFIRMATION REQUIRED`
- `PERMANENTLY UNRECOVERABLE`

Every production implementation must use one source state:

- `NOT STARTED`
- `SOURCE COMPLETE`
- `ASSEMBLED`
- `DEVICE VERIFIED`
- `BEHAVIOR MATCHED`
- `BLOCKED`

The evidence classification and implementation state are separate axes. Source
completion does not upgrade evidence, and strong evidence does not prove that
new source works on-device.

## Integrity procedure

Before using an artifact:

1. calculate its SHA-256;
2. compare it with this manifest;
3. stop if it differs;
4. identify whether the file is an authorized replacement;
5. update this manifest only through an explicit reviewed change.

No report may be silently replaced under an existing filename.
