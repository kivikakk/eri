fn main() {
    let mut module = hdl::Module::make("top");
    let led0 = hdl::Resource::find("led0");
    let counter = hdl::Signal::make("counter", 16);
    module.comb(&[led0.o.eq(counter.bit(-1))]);
    module.sync(&[counter.eq(&counter + 1)]);
    module.dump();
}

mod hdl {
    use std::borrow::Borrow;

    pub struct Module {
        name: String,
        combs: Vec<Stmt>,
        syncs: Vec<Stmt>,
    }

    impl Module {
        pub fn make(name: &str) -> Self {
            Module {
                name: name.to_string(),
                combs: vec![],
                syncs: vec![],
            }
        }

        pub fn dump(&self) {
            println!("=== module {} === ", self.name);
            println!("{} comb(s)", self.combs.len());
            for i in &self.combs {
                i.dump();
            }
            println!("{} sync(s)", self.syncs.len());
            for i in &self.syncs {
                i.dump();
            }
        }

        pub fn comb(&mut self, stmts: &[Stmt]) {
            self.combs.extend(stmts.iter().cloned());
        }

        pub fn sync(&mut self, stmts: &[Stmt]) {
            self.syncs.extend(stmts.iter().cloned());
        }
    }

    pub enum Where {
        Lv,
        Rv,
    }

    #[derive(Clone)]
    pub struct Signal {
        name: String,
        size: usize,
    }

    impl Signal {
        pub fn make(name: &str, size: usize) -> Self {
            Signal {
                name: name.to_string(),
                size,
            }
        }

        pub fn dump(&self, loc: Where) {
            match loc {
                Where::Lv => print!("<Signal {} ({})>", self.name, self.size),
                Where::Rv => print!("{}", self.name),
            }
        }

        pub fn eq<E: Borrow<Expr>>(&self, rhs: E) -> Stmt {
            Stmt::Eq(self.clone(), rhs.borrow().clone())
        }

        pub fn expr(&self) -> Expr {
            Expr::Signal(self.clone())
        }

        pub fn bit(&self, ix: isize) -> Expr {
            self.expr().bit(ix)
        }
    }

    impl core::ops::Add<isize> for &Signal {
        type Output = Expr;

        fn add(self, rhs: isize) -> Self::Output {
            self.expr() + rhs
        }
    }

    #[derive(Clone)]
    pub enum Stmt {
        Eq(Signal, Expr),
    }

    impl Stmt {
        pub fn dump(&self) {
            match self {
                Stmt::Eq(lv, rv) => {
                    lv.dump(Where::Lv);
                    print!(" = ");
                    rv.dump();
                    println!();
                }
            }
        }
    }

    #[derive(Clone)]
    pub enum Expr {
        Signal(Signal),
        Constant(isize),
        Bit(Box<Expr>, usize),
        Add(Box<Expr>, Box<Expr>),
    }

    impl Expr {
        pub fn boxed(&self) -> Box<Expr> {
            Box::new(self.clone())
        }

        pub fn dump(&self) {
            match self {
                Expr::Signal(s) => s.dump(Where::Rv),
                Expr::Constant(c) => print!("{}", c),
                Expr::Bit(e, ix) => {
                    e.dump();
                    print!("[{}]", ix);
                }
                Expr::Add(lhs, rhs) => {
                    print!("(");
                    lhs.dump();
                    print!(" + ");
                    rhs.dump();
                    print!(")");
                }
            }
        }

        pub fn size(&self) -> usize {
            match self {
                Expr::Signal(s) => s.size,
                Expr::Constant(_) => panic!("size of constant"),
                Expr::Bit(..) => 1,
                Expr::Add(lhs, rhs) => lhs.size().max(rhs.size()), // XXX
            }
        }

        pub fn bit(&self, ix: isize) -> Expr {
            Expr::Bit(
                self.boxed(),
                if ix >= 0 {
                    ix as usize
                } else {
                    ((self.size() as isize) + ix) as usize
                },
            )
        }
    }

    impl core::ops::Add<isize> for Expr {
        type Output = Expr;

        fn add(self, rhs: isize) -> Self::Output {
            Expr::Add(self.boxed(), Expr::Constant(rhs).boxed())
        }
    }

    pub struct Resource {
        name: String,
        pub o: Signal,
    }

    impl Resource {
        pub fn find(name: &str) -> Resource {
            Resource {
                name: name.to_string(),
                o: Signal::make(&format!("{name}.o"), 1),
            }
        }
    }
}
