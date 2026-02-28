Hello Word
**Software Workflow**

**OverView**

There is only one repo and one engineering is using github and the other wasnt, this is to help organzie the work the both engineers work on.


**Kyle's Workflow**


**Intial State**

Between tasks we assume kyle has the main branch checked out, also assume he is in sync with origin remote and doesnt have any files to commit and is updated with origin.


**Kyle gets a new task**

- Kyle will create a new branch of off main.
- kyle will then do a push to create a tracking branch.
- Kyle does his development.
- Kyle might do commits and pushes while he is working on the task.
- When the task is done, Kyle makes sure his local files are up to date with origin.
- Kyle creates a pr(pull request), Kyle merges his pull request (this way main has the new changes).
- Kyle can make a release (the release will notes will have an explaination of what is in the release).


**Zipfile Workflow**

The Initial State is the same as kyle's workflow.


**A new Zipfile arrives**

- Create a new branch of off main.
- Kyle will then do a push to create a tracking branch.
- Unzip the zip file in the directory
- Stage, Commit and push all the changes.
- Pull request of that branch, merge it then make a release.

**Have a meaning names for the branches to recognize it**

Have a synamtic version naming convention


okay hear me out, i am currently working on ptsc administration(admin@ptsc.gov.tt) and vmcott administration page(admin@vmcott.gov.tt) these pages should have all the options that those agencies can do on it so that nav bar has to change similar to the previous version but you find the right options for the nav bar because remember the workflow was an agency (that isnt vmcott) sends an rfq to vmcott and vmcott gets it in there rfq inbox then they convert their rfq to quotation then sends it back to the agency with jobs and parts that are needed, then ptsc gets it in their quotations inbox  and decides what from the quotation they want to accept like jobs or parts and some jobs use parts ofc  then they send it back as a purchase order then vmcott recieves it and currently doing work on the vehicle incase they see something wrong with the vehicle while fixing it they send another quotation with jobs or parts or both that can be done on the vehicle then ptsc can choose to accept that quotation or not whatever then completes the work on the vehicle and send the vehicle back with an invoice then that invoice goes in the agencies invoices aging tab i guess where all the invoices pile up and can be paid every month 2 or three months, also when vmcott sends back the vehicle they say when the next service/maintenance is due based on millage so that way the agency can see upcoming maintenance 

kyles newest workflow 

okay i want at least these , a person to the front of the building that receives the vehicle from the other agency, his job take the license plate of the vehicle and the name of the driver and put it in tthe system as received but his screen should just have a search bar and /qr code scanner that finds the vehicle on the system that makes him select it and a name of the driver (can be anyname), now how i want it when he enters the vehicle in the system, the system should have a status update it says vehicle received (or something like that) and the status bar should be on both vmcott and the agency so the agency sees the status being updated, then it goes to the inpsector to do fully diagonostic on the vehicle, when he is finished he can do a few things , say what jobs needs to be done on the vehicle and aditional notes, now that he is finished the status is updated saying inspection finished( or somethng to that degree) then the role of the person incharge of overseeing the inventory and searching multiple vendors( sending multiple vendors that usually have the items or parts necessary rfqs, and then multiple vendors sending their quotations, and i want to have a system in place that sort all the quotations from the vendors for the items requested and with the lowest prices one highlighted and the most frequent bought vendor rfq highlghted) then when the part is received or if vmcott has the part in stock, this is where the next role comes in the mechanics that gets a notification with current jobs ( or awaiting job completion, you think of a good name) then when a mechanic takes up a job or is assigned a job from the admin the status bar changed again to currently repairing/servicing vehicle, when finished the inspector lays with the mechanics that did the job and inspects the vehicle he then says what maintenance needs to be done in how much more kilometers driven( so for example checks the vehicle mileage and says in 5000 k.m you can come in to do a service) then after that the status changes again and says the vehicle is ready for pickup and an invoice is sent with the vehicle, something along those lines 